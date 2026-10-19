import 'package:medstation_core/medstation_core.dart';
import 'package:postgres/postgres.dart' hide Severity;

import '../auth.dart';
import '../db.dart';
import '../http.dart';

/// Users of one pharmacy (tenant). Several users share the tenant's stock,
/// catalog and check history; each action is attributed to its user.
class UserRepo {
  UserRepo(this.db, {required this.passwordIterations});
  final Db db;
  final int passwordIterations;

  Future<List<Map<String, dynamic>>> list(String pharmacyId) async {
    final r = await db.execute(
      Sql.named('SELECT id, email, full_name, role, active, created_at FROM users '
          'WHERE pharmacy_id = @p ORDER BY active DESC, full_name'),
      parameters: {'p': pharmacyId},
    );
    return [
      for (final x in r)
        {
          'id': x[0],
          'email': x[1],
          'fullName': x[2],
          'role': x[3],
          'active': x[4],
          'createdAt': (x[5] as DateTime).toUtc().toIso8601String(),
        }
    ];
  }

  Future<Map<String, dynamic>> create(AuthUser by,
      {required String email, required String fullName, required String password, required Role role}) async {
    if (role == Role.admin && by.role != Role.admin) throw ApiError.forbidden('Yönetici hesabını yalnızca yönetici açabilir');
    final e = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) throw ApiError.badRequest('Geçerli bir e-posta girin');
    if (password.length < 10) throw ApiError.badRequest('Parola en az 10 karakter olmalı');
    if (fullName.trim().length < 2) throw ApiError.badRequest('Ad soyad gerekli');
    final exists = await db.execute(Sql.named('SELECT 1 FROM users WHERE email = @e'), parameters: {'e': e});
    if (exists.isNotEmpty) throw ApiError(409, 'email_taken', 'Bu e-posta ile bir hesap var');
    final id = newId();
    await db.execute(
      Sql.named('INSERT INTO users (id, pharmacy_id, email, full_name, password_hash, role) '
          'VALUES (@id, @p, @e, @n, @h, @r)'),
      parameters: {
        'id': id,
        'p': by.pharmacyId,
        'e': e,
        'n': fullName.trim(),
        'h': hashPassword(password, iterations: passwordIterations),
        'r': role.name,
      },
    );
    await audit(db, by.id, 'user.create', entity: 'user', entityId: id, data: {'role': role.name});
    return (await list(by.pharmacyId)).firstWhere((u) => u['id'] == id);
  }

  Future<void> setActive(AuthUser by, String userId, bool active) async {
    if (userId == by.id && !active) throw ApiError.badRequest('Kendi hesabınızı devre dışı bırakamazsınız');
    final r = await db.execute(
      Sql.named('UPDATE users SET active = @a WHERE id = @u AND pharmacy_id = @p RETURNING role'),
      parameters: {'a': active, 'u': userId, 'p': by.pharmacyId},
    );
    if (r.isEmpty) throw ApiError.notFound('Kullanıcı bulunamadı');
    if (r.first[0] == 'admin' && by.role != Role.admin) throw ApiError.forbidden();
    if (!active) {
      await db.execute(Sql.named('UPDATE refresh_tokens SET revoked = true WHERE user_id = @u'), parameters: {'u': userId});
    }
    await audit(db, by.id, active ? 'user.activate' : 'user.deactivate', entity: 'user', entityId: userId);
  }
}

/// Supportive (commercial) products the pharmacy itself decides to suggest.
/// Kept apart from clinical logic: they never affect findings.
class CatalogRepo {
  CatalogRepo(this.db);
  final Db db;

  Future<List<Map<String, dynamic>>> list(String pharmacyId) async {
    final r = await db.execute(
      Sql.named('SELECT id, name, note, trigger_type, trigger_value, active FROM commercial_products '
          'WHERE pharmacy_id = @p ORDER BY active DESC, name'),
      parameters: {'p': pharmacyId},
    );
    return [
      for (final x in r)
        {'id': x[0], 'name': x[1], 'note': x[2], 'triggerType': x[3], 'triggerValue': x[4], 'active': x[5]}
    ];
  }

  Future<Map<String, dynamic>> create(AuthUser by,
      {required String name, String? note, required String triggerType, required String triggerValue}) async {
    if (!{'atc', 'ingredient'}.contains(triggerType)) throw ApiError.badRequest('Tetikleyici atc veya ingredient olmalı');
    final v = triggerType == 'atc' ? triggerValue.trim().toUpperCase() : baseIngredient(triggerValue);
    if (name.trim().isEmpty || v.isEmpty) throw ApiError.badRequest('Ürün adı ve tetikleyici gerekli');
    if (triggerType == 'atc' && !RegExp(r'^[A-Z][0-9A-Z]{0,6}$').hasMatch(v)) {
      throw ApiError.badRequest('ATC kodu öneki geçersiz (örn. J01 veya J01CR)');
    }
    final id = newId();
    await db.execute(
      Sql.named('INSERT INTO commercial_products (id, pharmacy_id, name, note, trigger_type, trigger_value, created_by) '
          'VALUES (@id, @p, @n, @note, @t, @v, @u)'),
      parameters: {'id': id, 'p': by.pharmacyId, 'n': name.trim(), 'note': note, 't': triggerType, 'v': v, 'u': by.id},
    );
    return (await list(by.pharmacyId)).firstWhere((x) => x['id'] == id);
  }

  Future<void> delete(String pharmacyId, String id) async {
    final r = await db.execute(Sql.named('DELETE FROM commercial_products WHERE id = @id AND pharmacy_id = @p'),
        parameters: {'id': id, 'p': pharmacyId});
    if (r.affectedRows == 0) throw ApiError.notFound('Ürün bulunamadı');
  }

  /// Catalog entries triggered by the prescription's drugs.
  Future<({bool connected, List<Map<String, dynamic>> items})> suggest(String pharmacyId, List<Drug> drugs) async {
    final all = (await list(pharmacyId)).where((x) => x['active'] == true).toList();
    if (all.isEmpty) return (connected: false, items: const <Map<String, dynamic>>[]);
    final atcs = drugs.map((d) => d.atc ?? '').where((a) => a.isNotEmpty).toList();
    final ings = {for (final d in drugs) ...d.ingredients.map((i) => baseIngredient(i.name))};
    final hits = <Map<String, dynamic>>[];
    for (final x in all) {
      final v = x['triggerValue'] as String;
      final because = x['triggerType'] == 'atc'
          ? atcs.where((a) => a.startsWith(v)).map((a) => 'ATC $a').firstOrNull
          : (ings.contains(v) ? v : null);
      if (because != null) hits.add({...x, 'because': because});
    }
    return (connected: true, items: hits);
  }
}
