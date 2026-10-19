import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:medstation_core/medstation_core.dart';
import 'package:medstation_server/medstation_server.dart';
import 'package:medstation_server/src/ingest/chunker.dart';
import 'package:postgres/postgres.dart';

/// Embeds KÜB/KT texts for the assistant.
///
/// Input is a manifest JSON: [{"product": "PAROL 500 MG TABLET" | "barcode":
/// "869...", "document": "KÜB", "file": "x.txt", "url": "https://...",
/// "date": "2025-04-01"}]. `bin/fetch_kubkt.dart` produces one from TİTCK.
/// A product name links the document to every pack whose name starts with it.
Future<void> main(List<String> args) async {
  final p = ArgParser()
    ..addOption('manifest', mandatory: true)
    ..addOption('version', mandatory: true)
    ..addOption('source', defaultsTo: 'TİTCK KÜB/KT metinleri');
  final a = p.parse(args);
  final config = Config.fromEnv();
  if (config.openAiKey == null) {
    stderr.writeln('OPENAI_API_KEY gerekli');
    exit(2);
  }
  final ai = OpenAiClient(apiKey: config.openAiKey!, model: config.openAiModel,
      embedModel: config.openAiEmbedModel, reasoningEffort: config.openAiReasoningEffort, baseUrl: config.openAiBaseUrl);
  final manifestFile = File(a['manifest'] as String);
  final entries = (jsonDecode(manifestFile.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final db = openDb(config.databaseUrl);
  await migrate(db);
  final drugs = DrugRepo(db);

  final sourceId = await db.runTx((tx) => ClinicalRepo.registerSource(tx,
      kind: 'documents', source: a['source'] as String, version: a['version'] as String, replace: false));
  var total = 0;
  for (final e in entries) {
    final doc = e['document'] as String;
    if (doc != 'KÜB' && doc != 'KT') throw FormatException('document KÜB veya KT olmalı');
    String product;
    String? drugId;
    if (e['barcode'] != null) {
      final drug = await drugs.byBarcode(e['barcode'] as String);
      if (drug == null) {
        stdout.writeln('Atlandı: ${e['barcode']} ilaç listesinde yok');
        continue;
      }
      product = drug.name;
      drugId = drug.id;
    } else {
      product = (e['product'] as String).trim();
      // Match on the name without a trailing "(ÜRETİM YERİ: …)" style note.
      final base = product.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '');
      final m = await db.execute(
          Sql.named("SELECT id FROM drugs WHERE name_fold LIKE @f || '%' ORDER BY length(name) LIMIT 1"),
          parameters: {'f': searchFold(base)});
      if (m.isEmpty) {
        stdout.writeln('Uyarı: "$product" ilaç listesinde eşleşmedi; belge yine de aranabilir.');
      } else {
        drugId = m.first[0] as String;
      }
    }
    final fold = searchFold(product.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), ''));
    final path = manifestFile.parent.uri.resolve(e['file'] as String).toFilePath();
    final chunks = chunkDocument(File(path).readAsStringSync());
    await db.execute(Sql.named('DELETE FROM doc_chunks WHERE name_fold = @f AND document = @doc'),
        parameters: {'f': fold, 'doc': doc});
    final slug = fold.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    for (var i = 0; i < chunks.length; i += 64) {
      final batch = chunks.sublist(i, (i + 64).clamp(0, chunks.length));
      final embs = await ai.embed([for (final c in batch) '$product ${c.section ?? ''}\n${c.text}']);
      for (var j = 0; j < batch.length; j++) {
        await db.execute(
          Sql.named('INSERT INTO doc_chunks (id, drug_id, drug_name, name_fold, document, section, url, document_date, '
              'content, embedding, source_id) VALUES (@id, @d, @n, @f, @doc, @s, @u, @dt, @c, CAST(@e AS vector), @src)'),
          parameters: {
            'id': '$slug:$doc:${i + j}',
            'd': drugId,
            'n': product,
            'f': fold,
            'doc': doc,
            's': batch[j].section,
            'u': e['url'],
            'dt': e['date'] == null ? null : dateValue(DateTime.parse(e['date'] as String)),
            'c': batch[j].text,
            'e': '[${embs[j].join(',')}]',
            'src': sourceId,
          },
        );
      }
    }
    if (e['url'] != null) {
      final n = await db.execute(
          Sql.named("UPDATE drugs SET ${doc == 'KÜB' ? 'kub_url' : 'kt_url'} = @u WHERE name_fold LIKE @f || '%'"),
          parameters: {'u': e['url'], 'f': fold});
      stdout.writeln('$product $doc: ${chunks.length} parça, ${n.affectedRows} ürüne bağlandı');
    } else {
      stdout.writeln('$product $doc: ${chunks.length} parça');
    }
    total += chunks.length;
  }
  await db.execute(Sql.named('UPDATE data_sources SET row_count = @n WHERE id = @id'),
      parameters: {'n': total, 'id': sourceId});
  await db.close();
}
