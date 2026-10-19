import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  StoredSession({required this.accessToken, required this.refreshToken, required this.user});
  final String accessToken;
  final String refreshToken;
  final Map<String, dynamic> user;
}

/// Tokens live only in the platform keystore/keychain.
class SessionStore {
  SessionStore([FlutterSecureStorage? s])
      : _s = s ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );
  final FlutterSecureStorage _s;

  Future<StoredSession?> read() async {
    final a = await _s.read(key: 'access');
    final r = await _s.read(key: 'refresh');
    final u = await _s.read(key: 'user');
    if (a == null || r == null || u == null) return null;
    return StoredSession(accessToken: a, refreshToken: r, user: jsonDecode(u) as Map<String, dynamic>);
  }

  Future<void> write(StoredSession s) async {
    await _s.write(key: 'access', value: s.accessToken);
    await _s.write(key: 'refresh', value: s.refreshToken);
    await _s.write(key: 'user', value: jsonEncode(s.user));
  }

  Future<void> updateTokens(String access, String refresh) async {
    await _s.write(key: 'access', value: access);
    await _s.write(key: 'refresh', value: refresh);
  }

  Future<void> clear() => _s.deleteAll();
}
