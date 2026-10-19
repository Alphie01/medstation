@Tags(['db'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:medstation_core/medstation_core.dart';
import 'package:medstation_server/medstation_server.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:postgres/postgres.dart' hide Severity;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Requires TEST_DATABASE_URL pointing at an empty, disposable database
/// (see docker-compose.yml). Skipped otherwise.
void main() {
  final url = Platform.environment['TEST_DATABASE_URL'];
  if (url == null) {
    test('integration (skipped: TEST_DATABASE_URL yok)', () {}, skip: true);
    return;
  }

  late Db db;
  late Handler app;
  late String token;
  final config = Config(env: AppEnv.test, databaseUrl: url, jwtSecret: 'x' * 40, passwordIterations: 1000);

  // Fake OpenAI: fixed embedding; answer cites c1 and an invented c9.
  final fakeAi = OpenAiClient(
    apiKey: 'test',
    model: 'm',
    embedModel: 'e',
    client: MockClient((req) async {
      if (req.url.path.endsWith('/embeddings')) {
        final n = (jsonDecode(req.body)['input'] as List).length;
        return http.Response(jsonEncode({
          'data': [for (var i = 0; i < n; i++) {'index': i, 'embedding': List.filled(1536, 0.1)}]
        }), 200);
      }
      final body = jsonDecode(req.body) as Map;
      expect(body['input'] as String, isNot(contains('12345678901')), reason: 'PII must be redacted');
      return http.Response(jsonEncode({
        'output': [
          {
            'type': 'message',
            'content': [
              {
                'type': 'output_text',
                'text': jsonEncode({
                  'answer': 'Yetişkinlerde günde 3 kez [c1]. Ayrıca [c9].',
                  'citations': ['c1', 'c9'],
                  'confidence': 'yuksek',
                  'insufficient': false,
                }),
              }
            ]
          }
        ]
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );

  Future<Response> call(String method, String path, {Object? body, bool auth = true}) async => app(Request(
        method,
        Uri.parse('http://x$path'),
        body: body == null ? null : jsonEncode(body),
        headers: {if (auth) 'authorization': 'Bearer $token'},
      ));
  Future<dynamic> ok(Response r, [int status = 200]) async {
    final s = await r.readAsString();
    expect(r.statusCode, status, reason: s);
    return jsonDecode(s);
  }

  setUpAll(() async {
    db = openDb(url);
    await db.execute('DROP SCHEMA public CASCADE; CREATE SCHEMA public;', queryMode: QueryMode.simple);
    await migrate(db, dir: 'migrations');
    final prov = DataProvenance(source: 'Test', version: 't', fetchedAt: DateTime.now(), isSample: true);
    DrugIngredient i(String n, double a, [double? ml]) => DrugIngredient(name: n, amount: a, unit: 'mg', perVolumeMl: ml);
    await db.runTx((tx) async {
      final src = await ClinicalRepo.registerSource(tx, kind: 'drugs', source: 'Test', version: 't', isSample: true);
      for (final d in [
        Drug(id: 'a1', barcode: '8699522095018', name: 'Augmentin', form: 'Film tablet', ingredients: [i('amoksisilin trihidrat', 875), i('klavulanik asit', 125)], provenance: prov),
        Drug(id: 'a2', name: 'Klamoks', form: 'Film tablet', ingredients: [i('amoksisilin', 875), i('klavulanik asit', 125)], provenance: prov),
        Drug(id: 'a3', name: 'Largopen', form: 'Tablet', ingredients: [i('amoksisilin', 1000)], provenance: prov),
        Drug(id: 'p1', name: 'Parol', form: 'Tablet', ingredients: [i('parasetamol', 500)], provenance: prov),
        Drug(id: 'p2', name: 'Tylol', form: 'Tablet', ingredients: [i('parasetamol', 500)], provenance: prov),
      ]) {
        await DrugRepo.upsert(tx, d, src);
      }
      await tx.execute("INSERT INTO pharmacies (id, name) VALUES ('ph1', 'Test Eczanesi')");
      await tx.execute(Sql.named("INSERT INTO users (id, pharmacy_id, email, full_name, password_hash, role) "
          "VALUES ('u1', 'ph1', 'e@x.com', 'Test Eczacı', @h, 'eczaci')"),
          parameters: {'h': hashPassword('parola-12345', iterations: 1000)});
      final docs = await ClinicalRepo.registerSource(tx, kind: 'documents', source: 'Test KÜB', version: 't');
      await tx.execute(Sql.named("INSERT INTO doc_chunks (id, drug_id, drug_name, document, section, content, embedding, source_id) "
          "VALUES ('k1', 'p1', 'Parol', 'KÜB', '4.2 Pozoloji', 'Yetişkinlerde günde 3-4 kez 500-1000 mg.', CAST(@e AS vector), @s)"),
          parameters: {'e': '[${List.filled(1536, 0.1).join(',')}]', 's': docs});
    });
    app = buildApp(Services(config: config, db: db, assistant: AssistantService(db, fakeAi)));
  });

  tearDownAll(() => db.close());

  test('auth required, login, refresh rotation', () async {
    expect((await call('GET', '/drugs/a1', auth: false)).statusCode, 401);
    final bad = await call('POST', '/auth/login', body: {'email': 'e@x.com', 'password': 'nope'}, auth: false);
    expect(bad.statusCode, 401);
    final l = await ok(await call('POST', '/auth/login', body: {'email': 'E@x.com ', 'password': 'parola-12345'}, auth: false));
    token = l['accessToken'] as String;
    final r = await ok(await call('POST', '/auth/refresh', body: {'refreshToken': l['refreshToken']}, auth: false));
    expect(r['accessToken'], isNotEmpty);
    final reuse = await call('POST', '/auth/refresh', body: {'refreshToken': l['refreshToken']}, auth: false);
    expect(reuse.statusCode, 401, reason: 'refresh tokens are single use');
  });

  test('ingredient search: incl vs exact counts, provenance and sample flag', () async {
    final r = await ok(await call('GET', '/drugs/search?ingredients=amoksisilin&mode=incl'));
    expect(r['counts'], {'incl': 3, 'exact': 1});
    expect((r['items'] as List).first['provenance']['isSample'], isTrue);
    final e = await ok(await call('GET', '/drugs/search?ingredients=amoksisilin,klavulanik%20asit&mode=exact'));
    expect((e['items'] as List).map((x) => x['id']), unorderedEquals(['a1', 'a2']));
    final t = await ok(await call('GET', '/drugs/search?q=AUGM'));
    expect((t['items'] as List).single['id'], 'a1');
    final s = await ok(await call('GET', '/ingredients/suggest?q=amok'));
    expect((s['items'] as List).first, {'name': 'amoksisilin', 'productCount': 3});
  });

  test('equivalents and karekod scan', () async {
    final eq = await ok(await call('GET', '/drugs/a1/equivalents'));
    expect((eq['items'] as List).map((x) => x['id']), ['a2']);
    final sc = await ok(await call('POST', '/drugs/scan', body: {'raw': '0108699522095018' '21SER1\u001d' '17281130' '10L1'}));
    expect(sc['drug']['id'], 'a1');
    expect(sc['code']['expiry'], '2028-11-30');
    expect((await call('POST', '/drugs/scan', body: {'raw': '0108699522095019'})).statusCode, 422);
  });

  test('prescription check uses server drug data and stores no identity', () async {
    final r = await ok(await call('POST', '/prescriptions/check', body: {
      'lines': [
        {'id': 'x', 'drugId': 'p1', 'posology': {'timesPerDay': 4, 'unitsPerDose': 2}},
        {'id': 'y', 'drugId': 'p2', 'posology': {'timesPerDay': 4, 'unitsPerDose': 2}},
      ],
      'patient': {'ageYears': 40},
    }));
    final types = (r['findings'] as List).map((f) => f['type']).toList();
    expect(types, contains('mukerrer'));
    expect(r['knowledge']['interactionDb'], isNull);
    expect(r['commercialSuggestions']['connected'], isFalse);
    final stored = await db.execute(Sql.named('SELECT request::text FROM prescription_checks WHERE id = @id'),
        parameters: {'id': r['checkId']});
    expect(stored.first[0] as String, isNot(contains('Parol')));

    final f = (r['findings'] as List).first['id'];
    await ok(await call('POST', '/prescriptions/${r['checkId']}/decisions', body: {'findingId': f, 'decision': 'onaylandi'}));
    final audit = await db.execute("SELECT count(*) FROM audit_log WHERE action = 'finding.onaylandi'");
    expect(audit.first[0], 1);
  });

  test('MEDULA returns not-authorized', () async {
    final r = await call('GET', '/prescriptions/medula/ABC1234');
    expect(r.statusCode, 501);
    expect(await r.readAsString(), contains('integration_not_authorized'));
  });

  test('assistant: retrieves, redacts PII, drops invented citations', () async {
    final a = await ok(await call('POST', '/assistant/ask',
        body: {'question': 'Parol dozu nedir? Hasta TC 12345678901'}));
    expect((a['citations'] as List).map((c) => c['chunkId']), ['k1']);
    expect(a['answer'], 'Yetişkinlerde günde 3 kez [1]. Ayrıca.');
  });

  test('stock: karekod in/out, duplicate serial, movement log, alerts', () async {
    String code(String serial, int days) =>
        '0108699522095018' '21$serial\u001d' '17${_yymmdd(DateTime.now().add(Duration(days: days)))}' '10L1';
    final s1 = await ok(await call('POST', '/stock/scan', body: {'raw': code('SER1', 20)}), 201);
    final itemId = s1['item']['id'];
    await ok(await call('POST', '/stock/scan', body: {'raw': code('SER2', 200)}), 201);
    expect((await call('POST', '/stock/scan', body: {'raw': code('SER1', 20)})).statusCode, 409);
    var alerts = await ok(await call('GET', '/stock/alerts?days=30'));
    expect((alerts['expiring'] as List).single['daysLeft'], 20);

    // Dispense the exact scanned pack.
    final out = await ok(await call('POST', '/stock/scan', body: {'raw': code('SER1', 20), 'direction': 'cikis'}));
    expect(out['batch']['serial'], 'SER1');
    expect(out['item']['quantity'], 1);
    // A pack that is not in stock is never swapped for another.
    final missing = await call('POST', '/stock/scan', body: {'raw': code('SERX', 20), 'direction': 'cikis'});
    expect(missing.statusCode, 404);
    // Plain barcode (no serial/lot) dispenses first-expiring batch.
    final fefo = await ok(await call('POST', '/stock/scan', body: {'raw': '8699522095018', 'direction': 'cikis'}));
    expect(fefo['batch']['serial'], 'SER2');
    expect((await call('POST', '/stock/scan', body: {'raw': '8699522095018', 'direction': 'cikis'})).statusCode, 409);
    // Returned pack can be taken in again.
    await ok(await call('POST', '/stock/scan', body: {'raw': code('SER1', 20)}), 201);

    final mv = (await ok(await call('GET', '/stock/movements')))['items'] as List;
    expect(mv.map((m) => m['direction']).toList(), ['giris', 'cikis', 'cikis', 'giris', 'giris']);
    expect(mv.first['userName'], 'Test Eczacı');

    final batchId = (s1['item']['batches'] as List).firstWhere((b) => b['serial'] == 'SER1')['id'];
    await ok(await call('PATCH', '/stock/batches/$batchId', body: {'quantity': 0, 'note': 'kırık'}));
    final mv2 = (await ok(await call('GET', '/stock/movements')))['items'] as List;
    expect(mv2.first['direction'], 'duzeltme');
    expect(mv2.first['quantity'], -1);

    await ok(await call('POST', '/stock/items', body: {'drugId': 'a2', 'criticalLevel': 5}), 201);
    alerts = await ok(await call('GET', '/stock/alerts'));
    final o = (alerts['outOfStock'] as List).firstWhere((x) => x['item']['id'] == itemId);
    expect((o['alternatives'] as List).single['drug']['id'], 'a2');
  });

  test('tenant users share stock; technician cannot manage users', () async {
    final u = await ok(await call('POST', '/pharmacy/users', body: {
      'email': 'tek@x.com', 'fullName': 'Teknisyen', 'password': 'parola-12345', 'role': 'teknisyen'
    }), 201);
    expect(u['role'], 'teknisyen');
    expect((await call('POST', '/pharmacy/users', body: {
      'email': 'adm@x.com', 'fullName': 'A', 'password': 'parola-12345', 'role': 'admin'
    })).statusCode, 403, reason: 'only admins create admins');
    final l = await ok(await call('POST', '/auth/login', body: {'email': 'tek@x.com', 'password': 'parola-12345'}, auth: false));
    final own = token;
    token = l['accessToken'] as String;
    final stock = await ok(await call('GET', '/stock'));
    expect((stock['items'] as List), isNotEmpty, reason: 'same tenant sees the same stock');
    expect((await call('GET', '/pharmacy/users')).statusCode, 403);
    token = own;
    await ok(await call('PATCH', '/pharmacy/users/${u['id']}', body: {'active': false}));
    expect((await call('POST', '/auth/login', body: {'email': 'tek@x.com', 'password': 'parola-12345'}, auth: false)).statusCode, 401);
  });

  test('commercial catalog is separate and trigger-based', () async {
    await ok(await call('POST', '/catalog', body: {'name': 'Probiyotik X', 'triggerType': 'atc', 'triggerValue': 'J01'}), 201);
    expect((await call('POST', '/catalog', body: {'name': 'Y', 'triggerType': 'atc', 'triggerValue': '1!'})).statusCode, 400);
    await db.execute("UPDATE drugs SET atc = 'J01CR02' WHERE id = 'a1'");
    final r = await ok(await call('POST', '/prescriptions/check', body: {
      'lines': [{'drugId': 'a1'}]
    }));
    final c = r['commercialSuggestions'];
    expect(c['connected'], isTrue);
    expect((c['items'] as List).single['name'], 'Probiyotik X');
    expect((c['items'] as List).single['because'], 'ATC J01CR02');
    expect((r['findings'] as List).any((f) => '${f['title']}'.contains('Probiyotik')), isFalse,
        reason: 'commercial items never appear among clinical findings');
  });

  test('assistant SSE: stages then validated result', () async {
    final res = await call('POST', '/assistant/ask/stream', body: {'question': 'Parol dozu?'});
    expect(res.headers['content-type'], startsWith('text/event-stream'));
    final body = await res.readAsString();
    final events = RegExp(r'event: (\w+)').allMatches(body).map((m) => m[1]).toList();
    expect(events, ['stage', 'stage', 'stage', 'result']);
    expect(body, contains('"chunkId":"k1"'));
  });

  test('production refuses active sample data', () async {
    expect(() => assertNoSampleData(db), throwsStateError);
  });
}

String _yymmdd(DateTime d) =>
    '${(d.year % 100).toString().padLeft(2, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
