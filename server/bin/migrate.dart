import 'package:medstation_server/medstation_server.dart';

Future<void> main() async {
  final db = openDb(Config.fromEnv().databaseUrl);
  await migrate(db);
  await db.close();
  print('Migrasyonlar uygulandı');
}
