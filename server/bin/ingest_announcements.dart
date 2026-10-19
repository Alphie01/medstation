import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:medstation_core/medstation_core.dart';
import 'package:medstation_server/medstation_server.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

/// Imports TİTCK announcements.
///
/// Two modes:
///  * `--json items.json`: [{"type": "geriCekme", "title": ..., "url": ...,
///    "publishedAt": "2026-10-01", "summary": ..., "barcodes": ["869..."]}]
///  * `--page https://www.titck.gov.tr/duyuru --pages 3`: parses the public listing using the CSS
///    selectors in config/titck_announcements.json. Check the site's terms
///    of use before scheduling this; selectors must be updated if the page
///    layout changes — unmatched items are reported, not guessed.
Future<void> main(List<String> args) async {
  final p = ArgParser()
    ..addOption('json')
    ..addOption('page')
    ..addOption('type', allowed: AnnouncementType.values.map((e) => e.name), help: 'Verilmezse etiket/başlıktan sınıflandırılır')
    ..addOption('pages', defaultsTo: '1')
    ..addOption('selectors', defaultsTo: 'config/titck_announcements.json')
    ..addOption('source', defaultsTo: 'TİTCK duyuruları');
  final a = p.parse(args);
  final items = <Map<String, dynamic>>[];
  String? url;
  if (a['json'] != null) {
    items.addAll((jsonDecode(File(a['json'] as String).readAsStringSync()) as List).cast());
  } else if (a['page'] != null) {
    url = a['page'] as String;
    final sel = jsonDecode(File(a['selectors'] as String).readAsStringSync()) as Map<String, dynamic>;
    final pages = int.parse(a['pages'] as String);
    for (var pg = 1; pg <= pages; pg++) {
      final pageUrl = pg == 1 ? url : '$url?page=$pg';
      final doc = html.parse(await _get(pageUrl));
      final nodes = doc.querySelectorAll(sel['item'] as String);
      if (nodes.isEmpty) stdout.writeln('Uyarı: $pageUrl içinde "${sel['item']}" bulunamadı; seçicileri kontrol edin.');
      for (final n in nodes) {
        final href = n.localName == 'a' ? n.attributes['href'] : n.querySelector('a')?.attributes['href'];
        final title = n.querySelector(sel['title'] as String)?.text.trim();
        final date = _trDate(n.querySelector(sel['date'] as String)?.text ?? '');
        final tags = [for (final t in n.querySelectorAll(sel['tags'] as String)) t.text.trim()];
        if (href == null || title == null || date == null) {
          stdout.writeln('Eşleşmedi: ${n.text.trim().split('\n').first}');
          continue;
        }
        final type = a['type'] as String? ?? _classify(title, tags);
        final link = Uri.parse(url).resolve(href).toString();
        // Recalls: link only barcodes literally printed on the detail page.
        final barcodes = type == 'geriCekme'
            ? RegExp(r'\b(86\d{11})\b').allMatches(await _get(link)).map((m) => m[1]!).toSet().toList()
            : const <String>[];
        items.add({
          'type': type,
          'title': title,
          'url': link,
          'publishedAt': date.toIso8601String(),
          'summary': [
            ...tags,
            n.querySelector(sel['summary'] as String)?.text.trim() ?? '',
          ].where((e) => e.isNotEmpty).join(' · '),
          'barcodes': barcodes,
        });
      }
    }
  } else {
    stderr.writeln(p.usage);
    exit(2);
  }

  final db = openDb(Config.fromEnv().databaseUrl);
  await migrate(db);
  await db.runTx((tx) async {
    final id = await ClinicalRepo.registerSource(tx,
        kind: 'announcements:${a['type'] ?? (a['page'] != null ? 'titck' : 'json')}', source: a['source'] as String,
        version: DateTime.now().toIso8601String().substring(0, 10), url: url);
    for (final it in items) {
      final ann = Announcement(
        id: sha1.convert(utf8.encode(it['url'] as String? ?? it['title'] as String)).toString(),
        type: AnnouncementType.values.byName(it['type'] as String),
        title: it['title'] as String,
        summary: it['summary'] as String?,
        url: it['url'] as String?,
        publishedAt: DateTime.parse(it['publishedAt'] as String),
        provenance: DataProvenance(source: a['source'] as String, version: '', fetchedAt: DateTime.now()),
      );
      await AnnouncementRepo.upsert(tx, ann, id);
      for (final b in (it['barcodes'] as List? ?? const []).cast<String>()) {
        await tx.execute(
            Sql.named('INSERT INTO recalls (barcode, announcement_id) VALUES (@b, @a) ON CONFLICT DO NOTHING'),
            parameters: {'b': b, 'a': ann.id});
      }
    }
    await ClinicalRepo.finishSource(tx, id, items.length, 0);
  });
  await db.close();
  stdout.writeln('${items.length} duyuru içe aktarıldı');
}

Future<String> _get(String url) async {
  final res = await http.get(Uri.parse(url), headers: {'user-agent': 'MedStationBot/0.1 (+eczane bilgi sistemi)'});
  if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode} $url');
  return utf8.decode(res.bodyBytes);
}

/// Type from TİTCK's own tag and the title. Keyword-based and conservative:
/// anything not clearly a recall/safety/price notice stays a general notice.
String _classify(String title, List<String> tags) {
  final t = searchFold('$title ${tags.join(' ')}');
  if (t.contains('geri cek') || t.contains('toplatil')) return 'geriCekme';
  if (t.contains('guvenlilik') || t.contains('farmakovijilans') || t.contains('dhpc') || t.contains('saglik mesleg')) {
    return 'guvenlilik';
  }
  if (t.contains('fiyat')) return 'fiyat';
  return 'duyuru';
}

DateTime? _trDate(String s) {
  final m = RegExp(r'(\d{1,2})[./](\d{1,2})[./](\d{4})').firstMatch(s);
  if (m == null) return null;
  return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
}
