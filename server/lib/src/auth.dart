import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import 'config.dart';
import 'db.dart';
import 'http.dart';

const _uuid = Uuid();
final _rand = Random.secure();

enum Role { eczaci, teknisyen, admin }

class AuthUser {
  AuthUser(this.id, this.pharmacyId, this.role);
  final String id;
  final String pharmacyId;
  final Role role;
}

extension AuthRequest on Request {
  AuthUser get user {
    final u = context['user'];
    if (u is! AuthUser) throw ApiError.unauthorized();
    return u;
  }
}

/// PBKDF2-HMAC-SHA256. Stored as `pbkdf2$<iter>$<salt b64>$<hash b64>`.
String hashPassword(String password, {int iterations = 120000}) {
  final salt = Uint8List.fromList(List.generate(16, (_) => _rand.nextInt(256)));
  final h = _pbkdf2(utf8.encode(password), salt, iterations, 32);
  return 'pbkdf2\$$iterations\$${base64Encode(salt)}\$${base64Encode(h)}';
}

bool verifyPassword(String password, String stored) {
  final p = stored.split('\$');
  if (p.length != 4 || p[0] != 'pbkdf2') return false;
  final iter = int.tryParse(p[1]);
  if (iter == null) return false;
  final expect = base64Decode(p[3]);
  final got = _pbkdf2(utf8.encode(password), base64Decode(p[2]), iter, expect.length);
  var diff = 0;
  for (var i = 0; i < expect.length; i++) {
    diff |= expect[i] ^ got[i];
  }
  return diff == 0;
}

Uint8List _pbkdf2(List<int> pass, List<int> salt, int iter, int len) {
  final hmac = Hmac(sha256, pass);
  final out = BytesBuilder();
  for (var block = 1; out.length < len; block++) {
    var u = hmac.convert([...salt, block >> 24, block >> 16 & 255, block >> 8 & 255, block & 255]).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iter; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return Uint8List.fromList(out.toBytes().sublist(0, len));
}

String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

String _randomToken() =>
    base64UrlEncode(List.generate(32, (_) => _rand.nextInt(256))).replaceAll('=', '');

class AuthService {
  AuthService(this.db, this.config);
  final Db db;
  final Config config;

  Future<Map<String, dynamic>> login(String email, String password) async {
    final r = await db.execute(
      Sql.named('SELECT id, pharmacy_id, role, password_hash, full_name, active '
          'FROM users WHERE email = @e'),
      parameters: {'e': email.trim().toLowerCase()},
    );
    // Same error for unknown user and wrong password.
    if (r.isEmpty) {
      verifyPassword(password, hashPassword('x', iterations: config.passwordIterations));
      throw ApiError(401, 'invalid_credentials', 'E-posta veya parola hatalı');
    }
    final u = r.first.toColumnMap();
    if (u['active'] != true || !verifyPassword(password, u['password_hash'] as String)) {
      throw ApiError(401, 'invalid_credentials', 'E-posta veya parola hatalı');
    }
    await audit(db, u['id'] as String, 'login');
    return _issue(u['id'] as String, u['pharmacy_id'] as String,
        Role.values.byName(u['role'] as String), u['full_name'] as String);
  }

  Future<Map<String, dynamic>> refresh(String token) async {
    final r = await db.execute(
      Sql.named('SELECT t.id, u.id AS uid, u.pharmacy_id, u.role, u.full_name '
          'FROM refresh_tokens t JOIN users u ON u.id = t.user_id '
          'WHERE t.token_hash = @h AND NOT t.revoked AND t.expires_at > now() AND u.active'),
      parameters: {'h': _sha(token)},
    );
    if (r.isEmpty) throw ApiError(401, 'invalid_refresh', 'Oturum süresi doldu');
    final m = r.first.toColumnMap();
    // Rotate: each refresh token is single-use.
    await db.execute(Sql.named('UPDATE refresh_tokens SET revoked = true WHERE id = @id'),
        parameters: {'id': m['id']});
    return _issue(m['uid'] as String, m['pharmacy_id'] as String,
        Role.values.byName(m['role'] as String), m['full_name'] as String);
  }

  Future<void> logout(String userId) async {
    await db.execute(Sql.named('UPDATE refresh_tokens SET revoked = true WHERE user_id = @u'),
        parameters: {'u': userId});
    await audit(db, userId, 'logout');
  }

  Future<Map<String, dynamic>> _issue(
      String uid, String pharmacyId, Role role, String name) async {
    final access = JWT({'ph': pharmacyId, 'role': role.name}, subject: uid, issuer: 'medstation')
        .sign(SecretKey(config.jwtSecret), expiresIn: config.accessTtl);
    final refresh = _randomToken();
    await db.execute(
      Sql.named('INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) '
          'VALUES (@id, @u, @h, @exp)'),
      parameters: {
        'id': _uuid.v4(),
        'u': uid,
        'h': _sha(refresh),
        'exp': DateTime.now().toUtc().add(config.refreshTtl),
      },
    );
    return {
      'accessToken': access,
      'refreshToken': refresh,
      'expiresIn': config.accessTtl.inSeconds,
      'user': {'id': uid, 'pharmacyId': pharmacyId, 'role': role.name, 'fullName': name},
    };
  }

  /// Rejects requests without a valid access token, except [public] paths.
  Middleware middleware({Set<String> public = const {}}) => (inner) => (req) {
        if (public.contains(req.url.path)) return inner(req);
        final h = req.headers['authorization'];
        if (h == null || !h.startsWith('Bearer ')) throw ApiError.unauthorized();
        try {
          final jwt = JWT.verify(h.substring(7), SecretKey(config.jwtSecret), issuer: 'medstation');
          final p = jwt.payload as Map<String, dynamic>;
          final user = AuthUser(jwt.subject!, p['ph'] as String, Role.values.byName(p['role'] as String));
          return inner(req.change(context: {'user': user}));
        } on JWTExpiredException {
          throw ApiError(401, 'token_expired', 'Oturum süresi doldu');
        } on JWTException {
          throw ApiError.unauthorized();
        }
      };
}

void requireRole(Request req, Set<Role> roles) {
  if (!roles.contains(req.user.role)) {
    throw ApiError.forbidden('Bu işlem için ${roles.map((r) => r.name).join('/')} yetkisi gerekir');
  }
}

Future<void> audit(Db db, String? userId, String action,
    {String? entity, String? entityId, Object? data}) async {
  await db.execute(
    Sql.named('INSERT INTO audit_log (user_id, action, entity, entity_id, data) '
        'VALUES (@u, @a, @e, @id, @d)'),
    parameters: {
      'u': userId,
      'a': action,
      'e': entity,
      'id': entityId,
      'd': data == null ? null : TypedValue(Type.jsonb, data),
    },
  );
}

String newId() => _uuid.v4();
