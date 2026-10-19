import 'dart:convert';

import 'package:medstation_core/medstation_core.dart';
import 'package:postgres/postgres.dart' hide Severity;

import '../db.dart';
import 'drug_repo.dart';

Map<String, dynamic> _jsonb(Object? v) =>
    (v is String ? jsonDecode(v) : v) as Map<String, dynamic>;

class ClinicalRepo {
  ClinicalRepo(this.db);
  final Db db;

  KnowledgeSnapshot? _cache;
  DateTime? _cachedAt;

  /// Verified reference data for the rule engine, cached for one minute.
  Future<KnowledgeSnapshot> snapshot() async {
    if (_cache != null && DateTime.now().difference(_cachedAt!) < const Duration(minutes: 1)) {
      return _cache!;
    }
    final src = await db.execute('''
      SELECT source AS s_source, version AS s_version, url AS s_url,
             fetched_at AS s_fetched_at, is_sample AS s_is_sample, id
      FROM data_sources WHERE kind = 'interactions' AND active
      ORDER BY fetched_at DESC LIMIT 1''');
    final interactions = await db.execute('''
      SELECT i.a, i.b, i.severity, i.summary, i.management, i.source
      FROM interactions i JOIN data_sources s ON s.id = i.source_id AND s.active''');
    final coverage = await db.execute('''
      SELECT c.ingredient FROM interaction_coverage c
      JOIN data_sources s ON s.id = c.source_id AND s.active''');
    final limits = await db.execute('''
      SELECT l.ingredient, l.population, l.unit, l.max_daily, l.max_daily_per_kg, l.source
      FROM dose_limits l JOIN data_sources s ON s.id = l.source_id AND s.active''');
    final recalls = await db.execute('SELECT DISTINCT barcode FROM recalls');

    _cache = KnowledgeSnapshot(
      interactionSource: src.isEmpty ? null : provenanceFromRow(src.first.toColumnMap()),
      interactions: [
        for (final r in interactions)
          Interaction(
            a: r[0] as String,
            b: r[1] as String,
            severity: Severity.parse(r[2] as String),
            summary: r[3] as String,
            management: r[4] as String?,
            source: SourceRef.fromJson(_jsonb(r[5])),
          ),
      ],
      interactionCoverage: {for (final r in coverage) r[0] as String},
      doseLimits: [
        for (final r in limits)
          DoseLimit(
            ingredient: r[0] as String,
            population: Population.values.byName(r[1] as String),
            unit: r[2] as String,
            maxDaily: (r[3] as num?)?.toDouble(),
            maxDailyPerKg: (r[4] as num?)?.toDouble(),
            source: SourceRef.fromJson(_jsonb(r[5])),
          ),
      ],
      recalledBarcodes: {for (final r in recalls) r[0] as String},
    );
    _cachedAt = DateTime.now();
    return _cache!;
  }

  void invalidate() => _cache = null;

  Future<List<Map<String, dynamic>>> provenance() async {
    final r = await db.execute('''
      SELECT kind, source, version, url, fetched_at, is_sample, row_count, skipped
      FROM data_sources WHERE active ORDER BY kind, fetched_at DESC''');
    return [
      for (final x in r)
        {
          'kind': x[0],
          'source': x[1],
          'version': x[2],
          'url': x[3],
          'fetchedAt': (x[4] as DateTime).toUtc().toIso8601String(),
          'isSample': x[5],
          'rowCount': x[6],
          'skipped': x[7],
        }
    ];
  }

  /// Registers a dataset import. Older imports of the same kind are
  /// deactivated when [replace] is true.
  static Future<int> registerSource(
    TxSession tx, {
    required String kind,
    required String source,
    required String version,
    String? url,
    bool isSample = false,
    bool replace = true,
  }) async {
    if (replace) {
      await tx.execute(Sql.named('UPDATE data_sources SET active = false WHERE kind = @k'),
          parameters: {'k': kind});
    }
    final r = await tx.execute(
      Sql.named('INSERT INTO data_sources (kind, source, version, url, is_sample) '
          'VALUES (@k, @s, @v, @u, @sample) RETURNING id'),
      parameters: {'k': kind, 's': source, 'v': version, 'u': url, 'sample': isSample},
    );
    return r.first[0] as int;
  }

  static Future<void> finishSource(TxSession tx, int id, int rows, int skipped) =>
      tx.execute(
        Sql.named('UPDATE data_sources SET row_count = @r, skipped = @s WHERE id = @id'),
        parameters: {'r': rows, 's': skipped, 'id': id},
      );
}
