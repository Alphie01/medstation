import 'dart:io';

import 'package:flutter/foundation.dart';

/// Build-time configuration. Pass `--dart-define=API_BASE=https://...` for
/// real deployments; release builds refuse plain HTTP.
abstract final class Env {
  static const _apiBase = String.fromEnvironment('API_BASE');

  static String get apiBase {
    if (_apiBase.isNotEmpty) {
      if (kReleaseMode && !_apiBase.startsWith('https://')) {
        throw StateError('Release build requires an https API_BASE');
      }
      return _apiBase;
    }
    if (kReleaseMode) throw StateError('API_BASE tanımlı değil');
    // Local dev server (see server/.env.example).
    return Platform.isAndroid ? 'http://10.0.2.2:8787' : 'http://localhost:8787';
  }
}
