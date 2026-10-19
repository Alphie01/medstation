import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:medstation_core/medstation_core.dart';
import 'package:postgres/postgres.dart';

import '../db.dart';
import '../repos/ops_repo.dart';

const titckUserAgent = 'MedStationBot/0.1 (+eczane bilgi sistemi)';

Future<String> fetchText(String url) async {
  final res = await http.get(Uri.parse(url), headers: {'user-agent': titckUserAgent}).timeout(const Duration(seconds: 60));
  if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode} $url');
  return utf8.decode(res.bodyBytes);
}

/// Type from TİTCK's own tag and the title. Keyword-based and conservative:
/// anything not clearly a recall/safety/price notice stays a general notice.
String classifyAnnouncement(String title, List<String> tags) {
  final t = searchFold('$title ${tags.join(' ')}');
  if (t.contains('geri cek') || t.contains('toplatil')) return 'geriCekme';
  if (t.contains('guvenlilik') || t.contains('farmakovijilans') || t.contains('dhpc') || t.contains('saglik mesleg')) {
    return 'guvenlilik';
  }
  if (t.contains('fiyat')) return 'fiyat';
  return 'duyuru';
}

DateTime? trDate(String s) {
  final m = RegExp(r'(\d{1,2})[./](\d{1,2})[./](\d{4})').firstMatch(s);
  if (m == null) return null;
  return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
}

/// Reads the public TİTCK announcement listing with the CSS selectors in
/// config/titck_announcements.json. For recalls, only barcodes literally
/// printed on the detail page are linked; nothing is matched by name.
Future<({List<Map<String, dynamic>> items, List<String> unmatched})> fetchTitckAnnouncements(
  String url,
  Map<String, dynamic> sel, {
  int pages = 1,
  String? forcedType,
}) async {
  final items = <Map<String, dynamic>>[];
  final unmatched = <String>[];
  for (var pg = 1; pg <= pages; pg++) {
    final pageUrl = pg == 1 ? url : '$url?page=$pg';
    final doc = html.parse(await fetchText(pageUrl));
    final nodes = doc.querySelectorAll(sel['item'] as String);
    if (nodes.isEmpty) unmatched.add('$pageUrl: "${sel['item']}" bulunamadı');
    for (final n in nodes) {
      final href = n.localName == 'a' ? n.attributes['href'] : n.querySelector('a')?.attributes['href'];
      final title = n.querySelector(sel['title'] as String)?.text.trim();
      final date = trDate(n.querySelector(sel['date'] as String)?.text ?? '');
      final tags = [for (final t in n.querySelectorAll(sel['tags'] as String)) t.text.trim()];
      if (href == null || title == null || date == null) {
        unmatched.add(n.text.trim().split('\n').first);
        continue;
      }
      final type = forcedType ?? classifyAnnouncement(title, tags);
      final link = Uri.parse(url).resolve(href).toString();
      final barcodes = type == 'geriCekme'
          ? RegExp(r'\b(86\d{11})\b').allMatches(await fetchText(link)).map((m) => m[1]!).toSet().toList()
          : const <String>[];
      items.add({
        'type': type,
        'title': title,
        'url': link,
        'publishedAt': date.toIso8601String(),
        'summary': [...tags, n.querySelector(sel['summary'] as String)?.text.trim() ?? ''].where((e) => e.isNotEmpty).join(' · '),
        'barcodes': barcodes,
      });
    }
  }
  return (items: items, unmatched: unmatched);
}

/// Upserts announcements under one stable source per [kind]; earlier
/// announcements that are no longer on the first pages stay visible.
Future<int> saveAnnouncements(Db db, List<Map<String, dynamic>> items,
    {required String kind, required String source, String? url}) async {
  return db.runTx((tx) async {
    final existing = await tx.execute(
      Sql.named('SELECT id FROM data_sources WHERE kind = @k AND active ORDER BY id DESC LIMIT 1'),
      parameters: {'k': kind},
    );
    final int id;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (existing.isEmpty) {
      id = (await tx.execute(
        Sql.named('INSERT INTO data_sources (kind, source, version, url) VALUES (@k, @s, @v, @u) RETURNING id'),
        parameters: {'k': kind, 's': source, 'v': today, 'u': url},
      ))
          .first[0] as int;
    } else {
      id = existing.first[0] as int;
      await tx.execute(Sql.named('UPDATE data_sources SET fetched_at = now(), version = @v WHERE id = @id'),
          parameters: {'v': today, 'id': id});
    }
    for (final it in items) {
      final ann = Announcement(
        id: sha1.convert(utf8.encode(it['url'] as String? ?? it['title'] as String)).toString(),
        type: AnnouncementType.values.byName(it['type'] as String),
        title: it['title'] as String,
        summary: it['summary'] as String?,
        url: it['url'] as String?,
        publishedAt: DateTime.parse(it['publishedAt'] as String),
        provenance: DataProvenance(source: source, version: '', fetchedAt: DateTime.now()),
      );
      await AnnouncementRepo.upsert(tx, ann, id);
      for (final b in (it['barcodes'] as List? ?? const []).cast<String>()) {
        await tx.execute(
            Sql.named('INSERT INTO recalls (barcode, announcement_id) VALUES (@b, @a) ON CONFLICT DO NOTHING'),
            parameters: {'b': b, 'a': ann.id});
      }
    }
    final total = await tx.execute(Sql.named('SELECT count(*) FROM announcements WHERE source_id = @id'), parameters: {'id': id});
    await tx.execute(Sql.named('UPDATE data_sources SET row_count = @n WHERE id = @id'),
        parameters: {'n': total.first[0], 'id': id});
    return items.length;
  });
}
