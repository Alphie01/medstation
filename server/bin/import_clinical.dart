import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:medstation_core/medstation_core.dart';
import 'package:medstation_server/medstation_server.dart';
import 'package:postgres/postgres.dart' hide Severity;

/// Imports verified interaction or dose-limit data from a JSON file.
///
/// Every record must carry a `source` object ({"source": "...", "section": ...,
/// "url": ..., "date": ...}); records without one are rejected. Use only data
/// you are licensed to use (e.g. a commercial interaction database, or values
/// transcribed from KÜB texts by a pharmacist).
///
///   dart run bin/import_clinical.dart --kind interactions --file x.json \
///     --source "Lisanslı DB adı" --version 2026.3 [--coverage ingredients.txt]
Future<void> main(List<String> args) async {
  final p = ArgParser()
    ..addOption('kind', mandatory: true, allowed: ['interactions', 'dose_limits'])
    ..addOption('file', mandatory: true)
    ..addOption('source', mandatory: true)
    ..addOption('version', mandatory: true)
    ..addOption('url')
    ..addOption('coverage', help: 'interactions: ingredients the database covers, one per line');
  final a = p.parse(args);
  final kind = a['kind'] as String;
  final records = (jsonDecode(File(a['file'] as String).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  final errors = <String>[];
  final interactions = <Interaction>[];
  final limits = <DoseLimit>[];
  for (var i = 0; i < records.length; i++) {
    final r = records[i];
    if (r['source'] is! Map || (r['source']['source'] as String?)?.isNotEmpty != true) {
      errors.add('#$i: kaynak yok');
      continue;
    }
    try {
      if (kind == 'interactions') {
        final x = Interaction.fromJson(r);
        if (x.severity == Severity.dogrulanamadi) throw const FormatException('severity');
        interactions.add(Interaction(
            a: baseIngredient(x.a), b: baseIngredient(x.b), severity: x.severity,
            summary: x.summary, management: x.management, source: x.source));
      } else {
        final d = DoseLimit.fromJson(r);
        limits.add(DoseLimit(
            ingredient: baseIngredient(d.ingredient), population: d.population, unit: d.unit,
            maxDaily: d.maxDaily, maxDailyPerKg: d.maxDailyPerKg, source: d.source));
      }
    } catch (e) {
      errors.add('#$i: $e');
    }
  }
  final coverage = a['coverage'] == null
      ? <String>{
          for (final x in interactions) ...[x.a, x.b],
        }
      : File(a['coverage'] as String)
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map(baseIngredient)
          .toSet();
  if (a['coverage'] == null && kind == 'interactions') {
    stdout.writeln('Uyarı: --coverage verilmedi; yalnızca kayıtlarda geçen maddeler "kapsanan" sayılır.');
  }
  stdout.writeln('Geçerli: ${interactions.length + limits.length}, reddedilen: ${errors.length}');
  errors.take(20).forEach((e) => stdout.writeln('  $e'));

  final db = openDb(Config.fromEnv().databaseUrl);
  await migrate(db);
  await db.runTx((tx) async {
    final id = await ClinicalRepo.registerSource(tx,
        kind: kind, source: a['source'] as String, version: a['version'] as String, url: a['url'] as String?);
    for (final x in interactions) {
      await tx.execute(
        Sql.named('INSERT INTO interactions (a, b, severity, summary, management, source, source_id) '
            'VALUES (@a, @b, @s, @sum, @m, @src, @id)'),
        parameters: {
          'a': x.a, 'b': x.b, 's': x.severity.name, 'sum': x.summary, 'm': x.management,
          'src': TypedValue(Type.jsonb, x.source.toJson()), 'id': id,
        },
      );
    }
    if (kind == 'interactions') {
      for (final c in coverage) {
        await tx.execute(
            Sql.named('INSERT INTO interaction_coverage (ingredient, source_id) VALUES (@c, @id) ON CONFLICT DO NOTHING'),
            parameters: {'c': c, 'id': id});
      }
    }
    for (final d in limits) {
      await tx.execute(
        Sql.named('INSERT INTO dose_limits (ingredient, population, unit, max_daily, max_daily_per_kg, source, source_id) '
            'VALUES (@i, @p, @u, @m, @k, @src, @id)'),
        parameters: {
          'i': d.ingredient, 'p': d.population.name, 'u': d.unit, 'm': d.maxDaily,
          'k': d.maxDailyPerKg, 'src': TypedValue(Type.jsonb, d.source.toJson()), 'id': id,
        },
      );
    }
    await ClinicalRepo.finishSource(tx, id, interactions.length + limits.length, errors.length);
  });
  await db.close();
}
