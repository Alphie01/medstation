import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:medstation_server/medstation_server.dart';
import 'package:medstation_server/src/ingest/titck_import.dart';

/// Imports TİTCK drug list files into the shared (all-tenant) drug table.
/// The `updater` service (bin/sync_titck.dart) does this automatically; this
/// command is for manual or offline imports.
///
///   ingest_titck --ruhsatli ruhsatli.xlsx --ruhsatli-version 2026-10-16 \
///     [--skrs skrs.xlsx --skrs-version 2026-10-13] [--dry-run]
Future<void> main(List<String> args) async {
  final p = ArgParser()
    ..addOption('ruhsatli', mandatory: true)
    ..addOption('ruhsatli-version', mandatory: true)
    ..addOption('ruhsatli-url')
    ..addOption('skrs')
    ..addOption('skrs-version')
    ..addOption('skrs-url')
    ..addOption('columns', defaultsTo: 'config/titck_columns.json')
    ..addFlag('dry-run');
  final a = p.parse(args);
  final importer = TitckImporter(jsonDecode(File(a['columns'] as String).readAsStringSync()) as Map<String, dynamic>);
  final ruhsatli = TitckFile(
      bytes: File(a['ruhsatli'] as String).readAsBytesSync(),
      version: a['ruhsatli-version'] as String,
      url: a['ruhsatli-url'] as String?);
  final skrs = a['skrs'] == null
      ? null
      : TitckFile(
          bytes: File(a['skrs'] as String).readAsBytesSync(),
          version: a['skrs-version'] as String? ?? '',
          url: a['skrs-url'] as String?);
  try {
    if (a['dry-run'] as bool) {
      final (:drugs, :report) = importer.parse(ruhsatli, skrs);
      report.summary().forEach(stdout.writeln);
      for (final x in report.skipped.take(15)) {
        stdout.writeln('  $x');
      }
      for (final x in report.samples) {
        stdout.writeln('  örnek: $x');
      }
      return;
    }
    final db = openDb(Config.fromEnv().databaseUrl);
    await migrate(db);
    final report = await importer.run(db, ruhsatli, skrs, log: stdout.writeln);
    report.summary().forEach(stdout.writeln);
    await db.close();
    stdout.writeln('İçe aktarma tamamlandı.');
  } on ImportFailure catch (e) {
    stderr.writeln(e.message);
    exit(2);
  }
}
