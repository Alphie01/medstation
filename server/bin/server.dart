import 'dart:async';
import 'dart:io';

import 'package:medstation_server/medstation_server.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  Logger.root.level = Level.INFO;
  // Request logs never include bodies (they may hold clinical data).
  Logger.root.onRecord.listen((r) => stderr.writeln('${r.time.toIso8601String()} ${r.level.name} ${r.loggerName}: ${r.message}${r.error == null ? '' : ' ${r.error}'}'));

  final config = Config.fromEnv();
  final db = openDb(config.databaseUrl);
  await migrate(db);
  if (config.isProd) await assertNoSampleData(db);

  final ai = config.openAiKey == null
      ? null
      : OpenAiClient(apiKey: config.openAiKey!, model: config.openAiModel,
          embedModel: config.openAiEmbedModel, reasoningEffort: config.openAiReasoningEffort, baseUrl: config.openAiBaseUrl);
  if (ai == null) Logger('server').warning('OPENAI_API_KEY yok: AI asistan kapalı');

  final services = Services(config: config, db: db, assistant: AssistantService(db, ai));
  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(buildApp(services));

  await purgeExpired(db, config.retentionDays);
  Timer.periodic(const Duration(hours: 24), (_) => purgeExpired(db, config.retentionDays));

  final server = await io.serve(handler, InternetAddress.anyIPv4, config.port);
  Logger('server').info('MedStation API ${config.env.name} :${server.port}');
}
