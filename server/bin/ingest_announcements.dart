import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:medstation_core/medstation_core.dart';
import 'package:medstation_server/medstation_server.dart';
import 'package:medstation_server/src/ingest/announcements_import.dart';

/// Imports TİTCK announcements (the `updater` service does this
/// automatically).
///
///  * `--page https://www.titck.gov.tr/duyuru --pages 3`: public listing,
///    CSS selectors in config/titck_announcements.json; unmatched items are
///    reported, not guessed. Recalls are linked only to barcodes printed on
///    the detail page.
///  * `--json items.json`: [{"type": "geriCekme", "title": ..., "url": ...,
///    "publishedAt": "2026-10-01", "summary": ..., "barcodes": ["869..."]}]
Future<void> main(List<String> args) async {
  final p = ArgParser()
    ..addOption('json')
    ..addOption('page')
    ..addOption('pages', defaultsTo: '1')
    ..addOption('type', allowed: AnnouncementType.values.map((e) => e.name), help: 'Verilmezse etiket/başlıktan sınıflandırılır')
    ..addOption('selectors', defaultsTo: 'config/titck_announcements.json')
    ..addOption('source', defaultsTo: 'TİTCK duyuruları');
  final a = p.parse(args);
  List<Map<String, dynamic>> items;
  String kind;
  if (a['json'] != null) {
    items = (jsonDecode(File(a['json'] as String).readAsStringSync()) as List).cast();
    kind = 'announcements:json';
  } else if (a['page'] != null) {
    final sel = jsonDecode(File(a['selectors'] as String).readAsStringSync()) as Map<String, dynamic>;
    final r = await fetchTitckAnnouncements(a['page'] as String, sel,
        pages: int.parse(a['pages'] as String), forcedType: a['type'] as String?);
    for (final x in r.unmatched) {
      stdout.writeln('Eşleşmedi: $x');
    }
    items = r.items;
    kind = 'announcements:titck';
  } else {
    stderr.writeln(p.usage);
    exit(2);
  }
  final db = openDb(Config.fromEnv().databaseUrl);
  await migrate(db);
  final n = await saveAnnouncements(db, items, kind: kind, source: a['source'] as String, url: a['page'] as String?);
  await db.close();
  stdout.writeln('$n duyuru içe aktarıldı');
}
