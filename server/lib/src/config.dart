import 'dart:io';

enum AppEnv { dev, prod, test }

/// Server configuration from environment variables. Secrets live here only;
/// the mobile app never receives them.
class Config {
  Config({
    required this.env,
    required this.databaseUrl,
    required this.jwtSecret,
    this.port = 8787,
    this.openAiKey,
    this.openAiModel = 'gpt-5-nano',
    this.openAiReasoningEffort,
    this.openAiEmbedModel = 'text-embedding-3-small',
    this.openAiBaseUrl = 'https://api.openai.com/v1',
    this.medulaEnabled = false,
    this.accessTtl = const Duration(minutes: 15),
    this.refreshTtl = const Duration(days: 30),
    this.retentionDays = 365,
    this.passwordIterations = 120000,
  });

  final AppEnv env;
  final String databaseUrl;
  final String jwtSecret;
  final int port;
  final String? openAiKey;
  final String openAiModel;

  /// For reasoning models (gpt-5 family): minimal | low | medium | high.
  final String? openAiReasoningEffort;
  final String openAiEmbedModel;
  final String openAiBaseUrl;

  /// Only true once an officially authorised MEDULA integration exists.
  final bool medulaEnabled;
  final Duration accessTtl;
  final Duration refreshTtl;

  /// Prescription check records older than this are purged (KVKK).
  final int retentionDays;
  final int passwordIterations;

  bool get isProd => env == AppEnv.prod;

  factory Config.fromEnv([Map<String, String>? e]) {
    e ??= Platform.environment;
    String req(String k) {
      final v = e![k];
      if (v == null || v.isEmpty) throw StateError('$k tanımlı değil');
      return v;
    }

    final env = AppEnv.values.byName(e['MEDSTATION_ENV'] ?? e['ETKEN_ENV'] ?? 'dev');
    final secret = req('JWT_SECRET');
    if (env == AppEnv.prod && secret.length < 32) {
      throw StateError('JWT_SECRET üretimde en az 32 karakter olmalı');
    }
    return Config(
      env: env,
      databaseUrl: req('DATABASE_URL'),
      jwtSecret: secret,
      port: int.parse(e['PORT'] ?? '8787'),
      openAiKey: e['OPENAI_API_KEY'],
      openAiModel: e['OPENAI_MODEL'] ?? 'gpt-5-nano',
      openAiReasoningEffort: e['OPENAI_REASONING_EFFORT'],
      openAiEmbedModel: e['OPENAI_EMBED_MODEL'] ?? 'text-embedding-3-small',
      openAiBaseUrl: e['OPENAI_BASE_URL'] ?? 'https://api.openai.com/v1',
      medulaEnabled: e['MEDULA_ENABLED'] == 'true',
      retentionDays: int.parse(e['RETENTION_DAYS'] ?? '365'),
    );
  }
}
