import 'package:args/args.dart';
import 'package:medstation_server/medstation_server.dart';
import 'package:postgres/postgres.dart';

/// dart run bin/create_user.dart --email a@b.c --name "Ad Soyad" --password ... \
///   --pharmacy "Eczane Adı" [--role eczaci]
Future<void> main(List<String> args) async {
  final p = ArgParser()
    ..addOption('email', mandatory: true)
    ..addOption('name', mandatory: true)
    ..addOption('password', mandatory: true)
    ..addOption('pharmacy', mandatory: true)
    ..addOption('role', defaultsTo: 'eczaci', allowed: ['eczaci', 'teknisyen', 'admin']);
  final a = p.parse(args);
  if ((a['password'] as String).length < 10) throw ArgumentError('Parola en az 10 karakter olmalı');
  final config = Config.fromEnv();
  final db = openDb(config.databaseUrl);
  await migrate(db);
  await db.runTx((tx) async {
    final ph = await tx.execute(Sql.named('SELECT id FROM pharmacies WHERE name = @n'),
        parameters: {'n': a['pharmacy']});
    final pharmacyId = ph.isEmpty ? newId() : ph.first[0] as String;
    if (ph.isEmpty) {
      await tx.execute(Sql.named('INSERT INTO pharmacies (id, name) VALUES (@id, @n)'),
          parameters: {'id': pharmacyId, 'n': a['pharmacy']});
    }
    await tx.execute(
      Sql.named('INSERT INTO users (id, pharmacy_id, email, full_name, password_hash, role) '
          'VALUES (@id, @p, @e, @n, @h, @r)'),
      parameters: {
        'id': newId(),
        'p': pharmacyId,
        'e': (a['email'] as String).toLowerCase(),
        'n': a['name'],
        'h': hashPassword(a['password'] as String, iterations: config.passwordIterations),
        'r': a['role'],
      },
    );
  });
  print('Kullanıcı oluşturuldu: ${a['email']}');
  await db.close();
}
