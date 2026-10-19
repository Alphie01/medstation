import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/providers.dart';
import '../../core/storage/session_store.dart';

enum AuthStatus { loading, signedOut, locked, signedIn }

class AuthState {
  const AuthState(this.status, {this.user, this.message});
  final AuthStatus status;
  final Map<String, dynamic>? user;
  final String? message;

  String get fullName => user?['fullName'] as String? ?? '';
  String get role => user?['role'] as String? ?? '';
}

class AuthController extends Notifier<AuthState> {
  static const biometricKey = 'biometric_lock';

  @override
  AuthState build() {
    _restore();
    return const AuthState(AuthStatus.loading);
  }

  bool get biometricEnabled => ref.read(prefsProvider).getBool(biometricKey) ?? false;

  Future<void> _restore() async {
    final s = await ref.read(sessionStoreProvider).read();
    if (s == null) {
      state = const AuthState(AuthStatus.signedOut);
    } else {
      state = AuthState(biometricEnabled ? AuthStatus.locked : AuthStatus.signedIn, user: s.user);
    }
  }

  Future<void> login(String email, String password) async {
    final api = ref.read(apiProvider);
    final r = await api.post('/auth/login', {'email': email, 'password': password});
    await ref.read(sessionStoreProvider).write(StoredSession(
          accessToken: r['accessToken'] as String,
          refreshToken: r['refreshToken'] as String,
          user: r['user'] as Map<String, dynamic>,
        ));
    state = AuthState(AuthStatus.signedIn, user: r['user'] as Map<String, dynamic>);
    ref.invalidate(metaProvider);
  }

  Future<bool> unlock() async {
    final ok = await LocalAuthentication().authenticate(
      localizedReason: 'MedStation\'u açmak için kimliğinizi doğrulayın',
    );
    if (ok) state = AuthState(AuthStatus.signedIn, user: state.user);
    return ok;
  }

  Future<void> setBiometric(bool on) async {
    if (on) {
      final la = LocalAuthentication();
      if (!await la.isDeviceSupported()) throw StateError('Bu cihazda biyometrik doğrulama yok');
      if (!await la.authenticate(localizedReason: 'Biyometrik kilidi etkinleştirin')) return;
    }
    await ref.read(prefsProvider).setBool(biometricKey, on);
  }

  Future<void> logout({String? message}) async {
    try {
      await ref.read(apiProvider).post('/auth/logout');
    } catch (_) {
      // Logging out locally must work offline too.
    }
    await ref.read(sessionStoreProvider).clear();
    state = AuthState(AuthStatus.signedOut, message: message);
  }

  void expired() {
    ref.read(sessionStoreProvider).clear();
    state = const AuthState(AuthStatus.signedOut, message: 'Oturum süresi doldu, tekrar giriş yapın.');
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
