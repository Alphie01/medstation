import 'package:medstation_core/medstation_core.dart';
import 'package:medstation_server/medstation_server.dart';
import 'package:postgres/postgres.dart' hide Severity;

/// Loads SAMPLE data for local development only. Every row is attached to a
/// data source with is_sample = true; the API marks it and the app shows an
/// "ÖRNEK VERİ" banner. Production refuses to start while it is active.
///
/// Barcodes use GS1 restricted-circulation prefix 200, so they can never
/// match a real product.
Future<void> main() async {
  final config = Config.fromEnv();
  if (config.isProd) throw StateError('Örnek veri üretim ortamına yüklenemez');
  final db = openDb(config.databaseUrl);
  await migrate(db);

  String bc(int n) {
    final body = '200${n.toString().padLeft(9, '0')}';
    var sum = 0;
    for (var i = 0; i < body.length; i++) {
      sum += (body.codeUnitAt(body.length - 1 - i) - 48) * (i.isEven ? 3 : 1);
    }
    return '$body${(10 - sum % 10) % 10}';
  }

  final prov = DataProvenance(source: 'ÖRNEK VERİ — gerçek ürün bilgisi değildir',
      version: 'dev', fetchedAt: DateTime.now(), isSample: true);
  DrugIngredient i(String n, double a, [double? ml]) =>
      DrugIngredient(name: n, amount: a, unit: 'mg', perVolumeMl: ml);
  var n = 0;
  Drug d(String name, String strength, String form, String firm, List<DrugIngredient> ings,
          {RxType rx = RxType.normal, String? atc, String? pack, bool recalled = false}) =>
      Drug(id: 'sample-${++n}', barcode: bc(n), name: '$name (örnek)', strength: strength, form: form,
          firm: '$firm (örnek)', pack: pack, atc: atc, rxType: rx, ingredients: ings,
          provenance: prov, recalled: recalled);

  final drugs = [
    d('Amoksiklav A', '875/125 mg', 'Film kaplı tablet', 'Firma A',
        [i('amoksisilin trihidrat', 875), i('klavulanik asit', 125)], atc: 'J01CR02', pack: '14 film tablet'),
    d('Amoksiklav B', '875/125 mg', 'Film kaplı tablet', 'Firma B',
        [i('amoksisilin', 875), i('potasyum klavulanat', 125)], atc: 'J01CR02', pack: '14 film tablet'),
    d('Amoksiklav Süspansiyon', '400/57 mg/5 ml', 'Oral süspansiyon', 'Firma A',
        [i('amoksisilin', 400, 5), i('klavulanik asit', 57, 5)], atc: 'J01CR02'),
    d('Amoksisilin Tek', '1000 mg', 'Tablet', 'Firma C', [i('amoksisilin', 1000)], atc: 'J01CA04'),
    d('Parasetamol A', '500 mg', 'Tablet', 'Firma D', [i('parasetamol', 500)],
        rx: RxType.receteSiz, atc: 'N02BE01', pack: '20 tablet'),
    d('Parasetamol B', '500 mg', 'Tablet', 'Firma E', [i('parasetamol', 500)],
        rx: RxType.receteSiz, atc: 'N02BE01', pack: '30 tablet'),
    d('Parasetamol Şurup', '120 mg/5 ml', 'Şurup', 'Firma D', [i('parasetamol', 120, 5)],
        rx: RxType.receteSiz, atc: 'N02BE01'),
    d('İbuprofen A', '400 mg', 'Film kaplı tablet', 'Firma F', [i('ibuprofen', 400)], atc: 'M01AE01'),
    d('İbuprofen Süspansiyon', '100 mg/5 ml', 'Oral süspansiyon', 'Firma D', [i('ibuprofen', 100, 5)],
        atc: 'M01AE01'),
    d('Metformin A', '1000 mg', 'Film kaplı tablet', 'Firma C', [i('metformin hidroklorür', 1000)], atc: 'A10BA02'),
    d('Metformin B', '1000 mg', 'Film kaplı tablet', 'Firma G', [i('metformin HCl', 1000)], atc: 'A10BA02'),
    d('Alprazolam Örnek', '0,5 mg', 'Tablet', 'Firma H',
        [DrugIngredient(name: 'alprazolam', amount: 0.5, unit: 'mg')], rx: RxType.yesil, atc: 'N05BA12'),
    d('Geri Çekilen Örnek', '10 mg', 'Tablet', 'Firma I', [i('örnek madde', 10)], recalled: true),
  ];

  await db.runTx((tx) async {
    await tx.execute("UPDATE data_sources SET active = false WHERE is_sample");
    final id = await ClinicalRepo.registerSource(tx,
        kind: 'drugs', source: prov.source, version: 'dev', isSample: true, replace: false);
    for (final x in drugs) {
      await DrugRepo.upsert(tx, x, id);
    }
    await ClinicalRepo.finishSource(tx, id, drugs.length, 0);

    // One sample dose limit so the overdose rule can be exercised locally.
    final lim = await ClinicalRepo.registerSource(tx,
        kind: 'dose_limits', source: prov.source, version: 'dev', isSample: true, replace: false);
    await tx.execute(
      Sql.named("INSERT INTO dose_limits (ingredient, population, unit, max_daily, source, source_id) "
          "VALUES ('parasetamol', 'yetiskin', 'mg', 4000, @s, @id)"),
      parameters: {
        's': TypedValue(Type.jsonb, {'source': 'ÖRNEK VERİ — doğrulanmış kaynakla değiştirin'}),
        'id': lim,
      },
    );

    final ann = await ClinicalRepo.registerSource(tx,
        kind: 'announcements:sample', source: prov.source, version: 'dev', isSample: true, replace: false);
    await AnnouncementRepo.upsert(tx, Announcement(
      id: 'sample-ann-1', type: AnnouncementType.geriCekme,
      title: 'Örnek geri çekme duyurusu (gerçek değildir)',
      summary: 'Geliştirme ortamı için örnek kayıt.',
      publishedAt: DateTime.now().subtract(const Duration(days: 2)), provenance: prov,
    ), ann);
  });
  await db.close();
  print('Örnek veri yüklendi (${drugs.length} ürün). Barkod örneği: ${bc(1)}');
}
