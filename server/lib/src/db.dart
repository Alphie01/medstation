import 'dart:io';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';

final _log = Logger('db');

typedef Db = Pool<void>;

Db openDb(String url) => Pool.withUrl(url);

/// Applies `migrations/*.sql` in name order, once each.
Future<void> migrate(Db db, {String dir = 'migrations'}) async {
  await db.execute('CREATE TABLE IF NOT EXISTS schema_migrations '
      '(version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())');
  final done = (await db.execute('SELECT version FROM schema_migrations'))
      .map((r) => r[0] as String)
      .toSet();
  final files = Directory(dir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final v = f.uri.pathSegments.last;
    if (done.contains(v)) continue;
    _log.info('migration $v');
    await db.runTx((tx) async {
      // Simple protocol allows multiple statements in one call.
      await tx.execute(f.readAsStringSync(), queryMode: QueryMode.simple);
      await tx.execute(
          Sql.named('INSERT INTO schema_migrations (version) VALUES (@v) '
              'ON CONFLICT DO NOTHING'),
          parameters: {'v': v});
    });
  }
}

/// Production must never serve sample data as real data.
Future<void> assertNoSampleData(Db db) async {
  final r = await db
      .execute('SELECT count(*) FROM data_sources WHERE is_sample AND active');
  final n = r.first[0] as int;
  if (n > 0) {
    throw StateError('Üretim ortamında $n örnek veri kaynağı etkin. '
        'Sunucu başlatılmadı; örnek veriyi kaldırın.');
  }
}

Map<String, dynamic> rowMap(ResultRow r) => r.toColumnMap();

/// Calendar date for a DATE column. Local-midnight DateTimes would shift a
/// day when the driver converts them to UTC (Türkiye is UTC+3).
TypedValue<DateTime> dateValue(DateTime d) =>
    TypedValue(Type.date, DateTime.utc(d.year, d.month, d.day));
