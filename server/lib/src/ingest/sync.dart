import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';

import '../db.dart';
import 'announcements_import.dart';
import 'titck_import.dart';

final _log = Logger('sync');

const ruhsatliPage = 'https://www.titck.gov.tr/dinamikmodul/85';
const skrsPage = 'https://www.titck.gov.tr/dinamikmodul/43';
const announcementsPage = 'https://www.titck.gov.tr/duyuru';

/// Arbitrary constant for pg_try_advisory_lock: only one updater runs.
const _lockKey = 72510425;

class Publication {
  Publication(this.url, this.version);
  final String url;

  /// yyyy-mm-dd
  final String version;
}

/// Newest XLSX on a TİTCK dynamic module page. Each table row holds the
/// document name, a dd/mm/yyyy date and the XLSX link.
Future<Publication> latestPublication(String pageUrl) async => parseLatestPublication(await fetchText(pageUrl), pageUrl);

Publication parseLatestPublication(String page, String pageUrl) {
  final doc = html.parse(page);
  Publication? best;
  for (final row in doc.querySelectorAll('tr')) {
    final link = row.querySelectorAll('a').map((a) => a.attributes['href'] ?? '').where((h) => h.toLowerCase().contains('.xlsx')).firstOrNull;
    final date = trDate(row.text);
    if (link == null || date == null) continue;
    final v = date.toIso8601String().substring(0, 10);
    if (best == null || v.compareTo(best.version) > 0) best = Publication(Uri.parse(pageUrl).resolve(link).toString(), v);
  }
  if (best == null) throw StateError('$pageUrl: XLSX bağlantısı bulunamadı; sayfa yapısı değişmiş olabilir.');
  return best;
}

Future<List<int>> _download(String url) async {
  final res = await http.get(Uri.parse(url), headers: {'user-agent': titckUserAgent}).timeout(const Duration(minutes: 5));
  if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode} $url');
  if (res.bodyBytes.length < 10000) throw StateError('$url beklenenden küçük (${res.bodyBytes.length} bayt)');
  return res.bodyBytes;
}

class SyncResult {
  SyncResult(this.status, this.lines);
  final String status;
  final List<String> lines;
}

/// One update run: imports a newer TİTCK drug list if one was published,
/// and refreshes announcements. Safe to call concurrently (advisory lock).
Future<SyncResult> syncOnce(
  Db db, {
  required Map<String, dynamic> columns,
  required Map<String, dynamic> announcementSelectors,
  int announcementPages = 2,
  bool force = false,
}) async {
  return db.withConnection((conn) async {
    final locked = (await conn.execute(Sql.named('SELECT pg_try_advisory_lock(@k)'), parameters: {'k': _lockKey})).first[0] as bool;
    if (!locked) return SyncResult('unchanged', ['Başka bir güncelleme sürüyor; atlandı.']);
    final runId = (await db.execute('INSERT INTO sync_runs DEFAULT VALUES RETURNING id')).first[0] as int;
    final lines = <String>[];
    var status = 'unchanged';
    void log(String s) {
      lines.add(s);
      _log.info(s);
    }

    try {
      // --- drug list
      final ruh = await latestPublication(ruhsatliPage);
      final skrs = await latestPublication(skrsPage);
      final cur = await db.execute(
          "SELECT meta FROM data_sources WHERE kind = 'drugs' AND active AND NOT is_sample ORDER BY fetched_at DESC LIMIT 1");
      final meta = cur.isEmpty ? null : _json(cur.first[0]);
      final same = meta != null && meta['ruhsatliUrl'] == ruh.url && meta['skrsUrl'] == skrs.url;
      if (same && !force) {
        log('İlaç listesi güncel (ruhsatlı ${ruh.version}, SKRS ${skrs.version}).');
      } else {
        log('Yeni yayın: ruhsatlı ${ruh.version}, SKRS ${skrs.version}; indiriliyor.');
        final report = await TitckImporter(columns).run(
          db,
          TitckFile(bytes: await _download(ruh.url), version: ruh.version, url: ruh.url),
          TitckFile(bytes: await _download(skrs.url), version: skrs.version, url: skrs.url),
          log: log,
        );
        report.summary().forEach(log);
        status = 'ok';
      }

      // --- announcements
      final ann = await fetchTitckAnnouncements(announcementsPage, announcementSelectors, pages: announcementPages);
      final n = await saveAnnouncements(db, ann.items, kind: 'announcements:titck', source: 'TİTCK duyuruları', url: announcementsPage);
      log('Duyurular: $n kayıt işlendi${ann.unmatched.isEmpty ? '' : ', ${ann.unmatched.length} öğe eşleşmedi'}.');
      if (status == 'unchanged' && n > 0) status = 'ok';

      await db.execute(Sql.named("UPDATE sync_runs SET finished_at = now(), status = @s, message = @m WHERE id = @id"),
          parameters: {'s': status, 'm': lines.join('\n'), 'id': runId});
      return SyncResult(status, lines);
    } catch (e) {
      log('Hata: $e');
      await db.execute(Sql.named("UPDATE sync_runs SET finished_at = now(), status = 'error', message = @m WHERE id = @id"),
          parameters: {'m': lines.join('\n'), 'id': runId});
      return SyncResult('error', lines);
    } finally {
      await conn.execute(Sql.named('SELECT pg_advisory_unlock(@k)'), parameters: {'k': _lockKey});
    }
  });
}

Map<String, dynamic>? _json(Object? v) => v == null ? null : (v is String ? jsonDecode(v) : v) as Map<String, dynamic>;
