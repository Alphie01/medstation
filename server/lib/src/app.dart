import 'dart:async';
import 'dart:convert';

import 'package:medstation_core/medstation_core.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'ai/assistant.dart';
import 'auth.dart';
import 'config.dart';
import 'db.dart';
import 'http.dart';
import 'medula.dart';
import 'repos/clinical_repo.dart';
import 'repos/drug_repo.dart';
import 'repos/ops_repo.dart';
import 'repos/tenant_repo.dart';

class Services {
  Services({
    required this.config,
    required this.db,
    required this.assistant,
    this.medula = const DisabledMedulaSource(),
  })  : auth = AuthService(db, config),
        drugs = DrugRepo(db),
        clinical = ClinicalRepo(db),
        announcements = AnnouncementRepo(db) {
    stock = StockRepo(db, drugs);
    favorites = FavoriteRepo(db, drugs);
    users = UserRepo(db, passwordIterations: config.passwordIterations);
    catalog = CatalogRepo(db);
  }

  final Config config;
  final Db db;
  final AuthService auth;
  final DrugRepo drugs;
  final ClinicalRepo clinical;
  final AnnouncementRepo announcements;
  final AssistantService assistant;
  final PrescriptionSource medula;
  late final StockRepo stock;
  late final FavoriteRepo favorites;
  late final UserRepo users;
  late final CatalogRepo catalog;
}

int _int(Object? v, String field, {int? min}) {
  final n = v is int ? v : int.tryParse('$v');
  if (n == null || (min != null && n < min)) {
    throw ApiError.badRequest('$field geçersiz');
  }
  return n;
}

String _str(Map<String, dynamic> b, String k) {
  final v = b[k];
  if (v is! String || v.trim().isEmpty) throw ApiError.badRequest('$k gerekli');
  return v.trim();
}

Map<String, dynamic> _gs1Json(Gs1Data g) => {
      'gtin': g.gtin,
      'barcode': g.barcode,
      'serial': g.serial,
      'lot': g.lot,
      'expiry': g.expiry?.toIso8601String().substring(0, 10),
      'ambiguous': g.ambiguous,
    };

Gs1Data _parseGs1(String raw) {
  try {
    return Gs1Parser.parse(raw);
  } on Gs1FormatException catch (e) {
    throw ApiError(422, 'invalid_code', 'Karekod okunamadı: ${e.message}');
  }
}

Handler buildApp(Services s) {
  final r = Router();
  final engine = RuleEngine();

  r.get('/health', (Request _) => json({'ok': true, 'env': s.config.env.name}));

  // --- auth
  r.post('/auth/login', (Request req) async {
    final b = await readJson(req);
    return json(await s.auth.login(_str(b, 'email'), _str(b, 'password')));
  });
  r.post('/auth/refresh', (Request req) async {
    final b = await readJson(req);
    return json(await s.auth.refresh(_str(b, 'refreshToken')));
  });
  r.post('/auth/logout', (Request req) async {
    await s.auth.logout(req.user.id);
    return json({'ok': true});
  });

  r.get('/meta/provenance', (Request req) async => json({
        'sources': await s.clinical.provenance(),
        'interactionDbConnected': (await s.clinical.snapshot()).interactionDbConnected,
        'medulaAvailable': s.medula.available,
        'assistantAvailable': s.assistant.ai != null,
        'commercialCatalogConnected': (await s.catalog.list(req.user.pharmacyId)).any((x) => x['active'] == true),
      }));

  // --- drugs
  r.get('/drugs/search', (Request req) async {
    final ings = (q(req, 'ingredients') ?? '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final mode = q(req, 'mode') == 'exact' ? MatchMode.exact : MatchMode.incl;
    final form = q(req, 'form');
    final res = await s.drugs.search(
      text: q(req, 'q'),
      ingredients: ings,
      mode: mode,
      form: form == null || form == 'all' ? null : FormGroup.parse(form),
    );
    return json({
      'items': res.items.map((d) => d.toJson()).toList(),
      'counts': {'incl': res.inclCount, 'exact': res.exactCount},
      'forms': res.formCounts,
    });
  });
  r.get('/drugs/barcode/<code>', (Request req, String code) async {
    final d = await s.drugs.byBarcode(code);
    if (d == null) throw ApiError.notFound('Bu barkodla kayıtlı ilaç yok');
    return json(d.toJson());
  });
  r.post('/drugs/scan', (Request req) async {
    final g = _parseGs1(_str(await readJson(req), 'raw'));
    final d = await s.drugs.byBarcode(g.barcode);
    return json({'code': _gs1Json(g), 'drug': d?.toJson()});
  });
  r.get('/drugs/<id>', (Request req, String id) async {
    final d = await s.drugs.byId(id);
    if (d == null) throw ApiError.notFound('İlaç bulunamadı');
    return json(d.toJson());
  });
  r.get('/drugs/<id>/equivalents', (Request req, String id) async {
    final d = await s.drugs.byId(id);
    if (d == null) throw ApiError.notFound('İlaç bulunamadı');
    return json({'items': (await s.drugs.equivalents(d)).map((e) => e.toJson()).toList()});
  });
  r.get('/ingredients/suggest', (Request req) async {
    final text = q(req, 'q');
    return json({'items': text == null ? [] : await s.drugs.suggestIngredients(text)});
  });
  r.get('/ingredients/top', (Request req) async => json({'items': await s.drugs.topIngredients()}));

  // --- prescriptions
  r.post('/prescriptions/check', (Request req) async {
    final b = await readJson(req);
    final rawLines = b['lines'];
    if (rawLines is! List || rawLines.isEmpty) throw ApiError.badRequest('En az bir ilaç gerekli');
    if (rawLines.length > 30) throw ApiError.badRequest('Bir reçetede en fazla 30 kalem olabilir');
    // Drug data is always resolved from our database, never trusted from the client.
    final ids = [for (final l in rawLines) _str(l as Map<String, dynamic>, 'drugId')];
    final drugs = {for (final d in await s.drugs.byIds(ids)) d.id: d};
    final lines = <PrescriptionLine>[];
    for (var i = 0; i < rawLines.length; i++) {
      final l = rawLines[i] as Map<String, dynamic>;
      final d = drugs[l['drugId']];
      if (d == null) throw ApiError.badRequest('Bilinmeyen ilaç: ${l['drugId']}');
      lines.add(PrescriptionLine(
        id: (l['id'] as String?) ?? 'l$i',
        drug: d,
        posology: l['posology'] == null
            ? const Posology()
            : Posology.fromJson(l['posology'] as Map<String, dynamic>),
        boxes: l['boxes'] as int? ?? 1,
      ));
    }
    final patient = b['patient'] == null
        ? const PatientContext()
        : PatientContext.fromJson(b['patient'] as Map<String, dynamic>);
    if ((patient.ageYears ?? 0) < 0 || (patient.ageYears ?? 0) > 130 ||
        (patient.weightKg ?? 1) <= 0 || (patient.weightKg ?? 0) > 300) {
      throw ApiError.badRequest('Yaş veya kilo geçersiz');
    }
    final rx = Prescription(
      lines: lines,
      patient: patient,
      rxType: b['rxType'] == null ? null : RxType.parse(b['rxType'] as String),
    );
    final kb = await s.clinical.snapshot();
    final findings = engine.check(rx, kb);

    final alternatives = <Map<String, dynamic>>[];
    for (final l in lines) {
      final eq = await s.drugs.equivalents(l.drug);
      alternatives.add({'lineId': l.id, 'items': eq.take(10).map((e) => e.toJson()).toList()});
    }

    final checkId = newId();
    final user = req.user;
    final commercial = await s.catalog.suggest(user.pharmacyId, [for (final l in lines) l.drug]);
    await s.db.execute(
      Sql.named('INSERT INTO prescription_checks (id, pharmacy_id, user_id, request, findings) '
          'VALUES (@id, @p, @u, @r, @f)'),
      parameters: {
        'id': checkId,
        'p': user.pharmacyId,
        'u': user.id,
        // Only drug ids, posology and anonymous age/weight are stored.
        'r': TypedValue(Type.jsonb, {
          'lines': [
            for (final l in lines) {'id': l.id, 'drugId': l.drug.id, 'posology': l.posology.toJson()}
          ],
          'patient': patient.toJson(),
          'rxType': rx.rxType?.name,
        }),
        'f': TypedValue(Type.jsonb, findings.map((f) => f.toJson()).toList()),
      },
    );
    await audit(s.db, user.id, 'prescription.check', entity: 'prescription_check', entityId: checkId,
        data: {'findings': findings.length});
    return json({
      'checkId': checkId,
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'lines': lines.map((l) => l.toJson()).toList(),
      'findings': findings.map((f) => f.toJson()).toList(),
      'knowledge': {
        'interactionDb': kb.interactionSource?.toJson(),
        'doseLimitCount': kb.doseLimits.length,
      },
      // Clinical alternatives: interchangeable products only.
      'clinicalAlternatives': alternatives,
      // Commercial/supportive products: the pharmacy's own catalog, a separate
      // and explicitly labelled channel that never influences findings.
      'commercialSuggestions': {'connected': commercial.connected, 'items': commercial.items},
    });
  });

  r.post('/prescriptions/<id>/decisions', (Request req, String id) async {
    requireRole(req, {Role.eczaci, Role.admin});
    final b = await readJson(req);
    final decision = _str(b, 'decision');
    if (!{'onaylandi', 'reddedildi', 'not'}.contains(decision)) {
      throw ApiError.badRequest('Karar onaylandi/reddedildi/not olmalı');
    }
    final user = req.user;
    final own = await s.db.execute(
        Sql.named('SELECT 1 FROM prescription_checks WHERE id = @id AND pharmacy_id = @p'),
        parameters: {'id': id, 'p': user.pharmacyId});
    if (own.isEmpty) throw ApiError.notFound('Kontrol kaydı bulunamadı');
    final findingId = _str(b, 'findingId');
    await s.db.execute(
      Sql.named('''
        INSERT INTO finding_decisions (check_id, finding_id, decision, note, user_id)
        VALUES (@c, @f, @d, @n, @u)
        ON CONFLICT (check_id, finding_id) DO UPDATE SET decision = EXCLUDED.decision,
          note = EXCLUDED.note, user_id = EXCLUDED.user_id, at = now()'''),
      parameters: {'c': id, 'f': findingId, 'd': decision, 'n': b['note'] as String?, 'u': user.id},
    );
    await audit(s.db, user.id, 'finding.$decision', entity: 'prescription_check', entityId: id,
        data: {'findingId': findingId});
    return json({'ok': true});
  });

  r.get('/prescriptions/medula/<code>', (Request req, String code) async {
    final lines = await s.medula.fetch(code, pharmacyId: req.user.pharmacyId);
    return json({'lines': lines.map((l) => l.toJson()).toList()});
  });

  // --- assistant
  r.post('/assistant/ask', (Request req) async {
    final b = await readJson(req);
    final ids = (b['drugIds'] as List? ?? const []).cast<String>();
    final a = await s.assistant.ask(_str(b, 'question'), drugIds: ids);
    await audit(s.db, req.user.id, 'assistant.ask', data: {'citations': a.citations.length});
    return json(a.toJson());
  });

  // Server-sent events: progress stages, then the validated answer. The
  // answer text is only sent after citation validation, never token by token.
  r.post('/assistant/ask/stream', (Request req) async {
    final b = await readJson(req);
    final ids = (b['drugIds'] as List? ?? const []).cast<String>();
    final question = _str(b, 'question');
    final user = req.user;
    final out = StreamController<List<int>>();
    void send(String event, Object data) =>
        out.add(utf8.encode('event: $event\ndata: ${jsonEncode(data)}\n\n'));
    unawaited(() async {
      try {
        final a = await s.assistant.ask(question,
            drugIds: ids, onStage: (stage, {passages}) => send('stage', {'stage': stage, 'passages': ?passages}));
        await audit(s.db, user.id, 'assistant.ask', data: {'citations': a.citations.length});
        send('result', a.toJson());
      } on ApiError catch (e) {
        send('error', {'code': e.code, 'message': e.message});
      } catch (_) {
        send('error', {'code': 'internal', 'message': 'Asistan yanıt veremedi'});
      } finally {
        await out.close();
      }
    }());
    return Response.ok(out.stream, headers: {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-store',
    }, context: {'shelf.io.buffer_output': false});
  });

  // --- stock
  r.get('/stock', (Request req) async =>
      json({'items': (await s.stock.list(req.user.pharmacyId)).map((e) => e.toJson()).toList()}));
  r.get('/stock/alerts', (Request req) async => json(
      await s.stock.alerts(req.user.pharmacyId, days: _int(q(req, 'days') ?? '90', 'days', min: 1))));
  r.post('/stock/items', (Request req) async {
    final b = await readJson(req);
    final it = await s.stock.upsertItem(
        req.user.pharmacyId, _str(b, 'drugId'), _int(b['criticalLevel'] ?? 0, 'criticalLevel', min: 0));
    return json(it.toJson(), status: 201);
  });
  r.post('/stock/items/<id>/batches', (Request req, String id) async {
    final b = await readJson(req);
    final exp = b['expiry'] as String?;
    final it = await s.stock.addBatch(req.user.pharmacyId, req.user.id, id,
        lot: b['lot'] as String?,
        serial: b['serial'] as String?,
        expiry: exp == null ? null : DateTime.parse(exp),
        quantity: _int(b['quantity'], 'quantity', min: 0));
    return json(it.toJson(), status: 201);
  });
  // Karekod/barcode stock movement: direction "giris" (receive) or "cikis"
  // (dispense). A serial-numbered karekod always moves exactly one pack.
  r.post('/stock/scan', (Request req) async {
    final b = await readJson(req);
    final direction = (b['direction'] as String?) ?? 'giris';
    if (direction != 'giris' && direction != 'cikis') throw ApiError.badRequest('direction giris veya cikis olmalı');
    final g = _parseGs1(_str(b, 'raw'));
    final d = await s.drugs.byBarcode(g.barcode);
    if (d == null) throw ApiError.notFound('Bu barkodla kayıtlı ilaç yok (${g.barcode})');
    final p = req.user.pharmacyId;
    final qty = g.serial != null ? 1 : _int(b['quantity'] ?? 1, 'quantity', min: 1);
    if (direction == 'cikis') {
      final r = await s.stock.dispense(p, req.user.id, d.id, serial: g.serial, lot: g.lot, expiry: g.expiry, quantity: qty);
      return json({'code': _gs1Json(g), 'direction': direction, 'item': r.item.toJson(), 'batch': r.batch.toJson()});
    }
    final item = (await s.stock.list(p)).where((i) => i.drugId == d.id).firstOrNull ??
        await s.stock.upsertItem(p, d.id, 0);
    final it = await s.stock.addBatch(p, req.user.id, item.id,
        lot: g.lot, serial: g.serial, expiry: g.expiry, quantity: qty);
    return json({'code': _gs1Json(g), 'direction': direction, 'item': it.toJson()}, status: 201);
  });
  r.get('/stock/movements', (Request req) async =>
      json({'items': await s.stock.movements(req.user.pharmacyId, limit: _int(q(req, 'limit') ?? '100', 'limit', min: 1))}));
  r.patch('/stock/batches/<id>', (Request req, String id) async {
    final b = await readJson(req);
    await s.stock.setBatchQuantity(req.user.pharmacyId, req.user.id, id, _int(b['quantity'], 'quantity', min: 0),
        note: b['note'] as String?);
    return json({'ok': true});
  });
  r.delete('/stock/items/<id>', (Request req, String id) async {
    await s.stock.deleteItem(req.user.pharmacyId, id);
    return json({'ok': true});
  });

  // --- tenant users (same pharmacy share stock, catalog and history)
  r.get('/pharmacy/users', (Request req) async {
    requireRole(req, {Role.eczaci, Role.admin});
    return json({'items': await s.users.list(req.user.pharmacyId)});
  });
  r.post('/pharmacy/users', (Request req) async {
    requireRole(req, {Role.eczaci, Role.admin});
    final b = await readJson(req);
    final role = Role.values.asNameMap()[b['role']];
    if (role == null) throw ApiError.badRequest('Rol eczaci, teknisyen veya admin olmalı');
    return json(
        await s.users.create(req.user,
            email: _str(b, 'email'), fullName: _str(b, 'fullName'), password: _str(b, 'password'), role: role),
        status: 201);
  });
  r.patch('/pharmacy/users/<id>', (Request req, String id) async {
    requireRole(req, {Role.eczaci, Role.admin});
    final b = await readJson(req);
    if (b['active'] is! bool) throw ApiError.badRequest('active gerekli');
    await s.users.setActive(req.user, id, b['active'] as bool);
    return json({'ok': true});
  });

  // --- pharmacy's supportive (commercial) product catalog
  r.get('/catalog', (Request req) async => json({'items': await s.catalog.list(req.user.pharmacyId)}));
  r.post('/catalog', (Request req) async {
    requireRole(req, {Role.eczaci, Role.admin});
    final b = await readJson(req);
    return json(
        await s.catalog.create(req.user,
            name: _str(b, 'name'),
            note: b['note'] as String?,
            triggerType: _str(b, 'triggerType'),
            triggerValue: _str(b, 'triggerValue')),
        status: 201);
  });
  r.delete('/catalog/<id>', (Request req, String id) async {
    requireRole(req, {Role.eczaci, Role.admin});
    await s.catalog.delete(req.user.pharmacyId, id);
    return json({'ok': true});
  });

  // --- announcements
  r.get('/announcements', (Request req) async {
    final t = q(req, 'type');
    final type = t == null ? null : AnnouncementType.values.asNameMap()[t];
    if (t != null && type == null) throw ApiError.badRequest('Geçersiz duyuru türü');
    return json({'items': (await s.announcements.list(type: type)).map((e) => e.toJson()).toList()});
  });

  // --- favorites
  r.get('/favorites', (Request req) async =>
      json({'items': (await s.favorites.list(req.user.id)).map((e) => e.toJson()).toList()}));
  r.put('/favorites/<drugId>', (Request req, String drugId) async {
    await s.favorites.add(req.user.id, drugId);
    return json({'ok': true});
  });
  r.delete('/favorites/<drugId>', (Request req, String drugId) async {
    await s.favorites.remove(req.user.id, drugId);
    return json({'ok': true});
  });

  r.all('/<ignored|.*>', (Request _) => throw ApiError.notFound('Uç nokta yok'));

  return const Pipeline()
      .addMiddleware(errorHandler())
      .addMiddleware(securityHeaders())
      .addMiddleware(s.auth.middleware(public: {'health', 'auth/login', 'auth/refresh'}))
      .addHandler(r.call);
}

/// Deletes prescription checks older than the retention period (KVKK).
Future<int> purgeExpired(Db db, int retentionDays) async {
  final r = await db.execute(
    Sql.named("DELETE FROM prescription_checks WHERE created_at < now() - make_interval(days => @d)"),
    parameters: {'d': retentionDays},
  );
  return r.affectedRows;
}
