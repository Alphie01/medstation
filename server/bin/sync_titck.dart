import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:medstation_server/medstation_server.dart';

/// Keeps TİTCK data current.
///
///   sync_titck --once            # one run
///   sync_titck --every 6h        # run now, then every 6 hours (docker "updater")
///   sync_titck --once --force    # re-import even if the files are unchanged
Future<void> main(List<String> args) async {
  final p = ArgParser()
    ..addFlag('once')
    ..addOption('every', defaultsTo: '6h', help: 'Örn. 30m, 6h, 1d')
    ..addFlag('force')
    ..addOption('announcement-pages', defaultsTo: '2')
    ..addOption('columns', defaultsTo: 'config/titck_columns.json')
    ..addOption('selectors', defaultsTo: 'config/titck_announcements.json');
  final a = p.parse(args);
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) => stdout.writeln('${r.time.toIso8601String()} ${r.loggerName}: ${r.message}'));

  final db = openDb(Config.fromEnv().databaseUrl);
  await migrate(db);
  Map<String, dynamic> load(String f) => jsonDecode(File(f).readAsStringSync()) as Map<String, dynamic>;

  Future<String> run() async {
    final r = await syncOnce(
      db,
      columns: load(a['columns'] as String),
      announcementSelectors: load(a['selectors'] as String),
      announcementPages: int.parse(a['announcement-pages'] as String),
      force: a['force'] as bool,
    );
    return r.status;
  }

  if (a['once'] as bool) {
    final s = await run();
    await db.close();
    exit(s == 'error' ? 1 : 0);
  }

  final every = _duration(a['every'] as String);
  Logger('sync').info('Otomatik güncelleme: her ${a['every']}');
  while (true) {
    await run();
    await Future<void>.delayed(every);
  }
}

Duration _duration(String s) {
  final m = RegExp(r'^(\d+)([mhd])$').firstMatch(s.trim());
  if (m == null) throw FormatException('Süre geçersiz: $s (örn. 30m, 6h, 1d)');
  final n = int.parse(m[1]!);
  return switch (m[2]) { 'm' => Duration(minutes: n), 'h' => Duration(hours: n), _ => Duration(days: n) };
}
