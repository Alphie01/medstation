import 'dart:io';

import 'package:flutter/foundation.dart';

/// Build-time configuration from `app/.env`, passed with
/// `flutter run --dart-define-from-file=.env` (see `.env.example`).
abstract final class Env {
  static const _apiBase = String.fromEnvironment('API_BASE');

  /// Release builds require https unless this is explicitly enabled; tokens
  /// and prescription data travel over this connection (KVKK).
  static const _allowInsecure = bool.fromEnvironment('ALLOW_INSECURE_HTTP');

  static String get apiBase {
    if (_apiBase.isNotEmpty) {
      if (kReleaseMode && !_apiBase.startsWith('https://') && !_allowInsecure) {
        throw StateError('Release build requires an https API_BASE (or ALLOW_INSECURE_HTTP=true)');
      }
      return _apiBase.endsWith('/') ? _apiBase.substring(0, _apiBase.length - 1) : _apiBase;
    }
    if (kReleaseMode) throw StateError('API_BASE tanımlı değil; app/.env dosyasını --dart-define-from-file ile verin');
    // Local dev server (see server/.env.example).
    return Platform.isAndroid ? 'http://10.0.2.2:8787' : 'http://localhost:8787';
  }
}
