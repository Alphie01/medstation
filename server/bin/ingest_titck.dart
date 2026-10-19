import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:medstation_core/medstation_core.dart';
import 'package:medstation_server/medstation_server.dart';
import 'package:medstation_server/src/ingest/titck_parse.dart';
import 'package:medstation_server/src/ingest/xlsx_reader.dart';

/// Imports the TİTCK drug list into the shared (all-tenant) drug table.
///
///   dart run bin/ingest_titck.dart \
///     --ruhsatli RuhsatliBeseriTibbiUrunlerListesi.xlsx --ruhsatli-version 2026-10-16 \
///     [--skrs skrs_erecete.xlsx --skrs-version 2026-10-13] [--dry-run]
///
/// * Ruhsatlı Beşeri Tıbbi Ürünler Listesi (dinamikmodul/85): barcode, name,
///   active ingredient, ATC, license holder, license suspension.
/// * SKRS E-Reçete İlaç Listesi (dinamikmodul/43): prescription type and
///   active/passive status, merged by barcode.
///
/// Invalid rows are skipped and reported. Unparseable compositions keep the
/// source text with no ingredients; amounts are attached only to
/// single-ingredient products. Prices are not in these lists and stay empty.
Future<void> main(List<String> args) async {
  final p = ArgParser()
    ..addOption('ruhsatli', mandatory: true)
    ..addOption('ruhsatli-version', mandatory: true)
    ..addOption('ruhsatli-url', defaultsTo: 'https://www.titck.gov.tr/dinamikmodul/85')
    ..addOption('skrs')
    ..addOption('skrs-version')
    ..addOption('columns', defaultsTo: 'config/titck_columns.json')
    ..addFlag('dry-run');
  final a = p.parse(args);
  final cfg = jsonDecode(File(a['columns'] as String).readAsStringSync()) as Map<String, dynamic>;

  final ruhsatli = _table(a['ruhsatli'] as String, cfg['ruhsatli'] as Map<String, dynamic>);
  final skrs = a['skrs'] == null ? null : _skrsIndex(a['skrs'] as String, cfg['skrs'] as Map<String, dynamic>);

  final version = a['ruhsatli-version'] as String;
  final source = skrs == null
      ? 'TİTCK Ruhsatlı Beşeri Tıbbi Ürünler Listesi'
      : 'TİTCK Ruhsatlı Ürünler + SKRS E-Reçete Listesi';
  final prov = DataProvenance(
    source: source,
    version: skrs == null ? version : '$version / SKRS ${a['skrs-version'] ?? ''}'.trim(),
    url: a['ruhsatli-url'] as String,
    fetchedAt: DateTime.now().toUtc(),
  );

  final drugs = <Drug>[];
  final skipped = <String>[];
  final seen = <String>{};
  var unparsed = 0, withAmount = 0, suspended = 0;
  final badCheck = <String>[];
  for (final (rowNo, row) in ruhsatli.rows) {
    String? c(String f) => ruhsatli.cell(row, f);
    final barcode = c('barcode')?.replaceAll(RegExp(r'\D'), '');
    final name = c('name');
    final ingCell = c('ingredients');
    if (barcode == null && name == null) continue;
    if (barcode == null || !RegExp(r'^\d{8,14}$').hasMatch(barcode)) {
      skipped.add('Satır $rowNo: geçersiz barkod "${c('barcode')}"');
      continue;
    }
    // Some published barcodes fail the GS1 check digit. They are imported as
    // published (name search still finds them) and reported; a scanned
    // karekod can never match them.
    if (!Gs1Parser.isValidGtin(barcode.padLeft(14, '0'))) badCheck.add(barcode);
    if (name == null) {
      skipped.add('Satır $rowNo: ürün adı boş');
      continue;
    }
    if (!seen.add(barcode)) {
      skipped.add('Satır $rowNo: tekrar eden barkod $barcode');
      continue;
    }
    final parsed = ingCell == null
        ? (ingredients: const <DrugIngredient>[], raw: null)
        : ingredientsFrom(ingCell, name);
    if (parsed.ingredients.isEmpty) unparsed++;
    if (parsed.ingredients.any((i) => i.amount != null)) withAmount++;
    final lic = LicenseStatus.fromCode(int.tryParse(c('license') ?? ''));
    if (lic.suspended) suspended++;
    final s = skrs?[barcode];
    drugs.add(Drug(
      id: 'tr-$barcode',
      barcode: barcode,
      name: name,
      firm: c('firm'),
      form: formFromName(name),
      strength: strengthFromName(name)?.label,
      pack: packFromName(name),
      atc: c('atc'),
      rxType: s == null ? RxType.bilinmiyor : rxFrom(s.rx),
      marketStatus: s == null ? MarketStatus.bilinmiyor : s.status,
      licenseStatus: lic,
      compositionText: parsed.raw,
      ingredients: parsed.ingredients,
      provenance: prov,
    ));
  }

  stdout.writeln('Okunan: ${drugs.length}, atlanan: ${skipped.length}');
  stdout.writeln('  bileşimi ayrıştırılamayan (kaynak metin saklandı): $unparsed');
  stdout.writeln('  etken madde miktarı atanan (tek etkenli): $withAmount');
  stdout.writeln('  ruhsatı askıda: $suspended');
  stdout.writeln('  kontrol hanesi hatalı barkod (kaynaktaki gibi alındı): ${badCheck.length}');
  if (skrs != null) {
    stdout.writeln('  SKRS ile eşleşen: ${drugs.where((d) => d.marketStatus != MarketStatus.bilinmiyor).length}');
  }
  for (final x in skipped.take(15)) {
    stdout.writeln('  $x');
  }
  if (a['dry-run'] as bool) {
    for (final d in drugs.where((d) => d.ingredients.length > 1).take(3)) {
      stdout.writeln('  örnek: ${d.name} → ${d.ingredients.map((i) => i.name).join(' | ')} [${d.rxType.name}, ${d.marketStatus.name}]');
    }
    return;
  }

  final db = openDb(Config.fromEnv().databaseUrl);
  await migrate(db);
  await db.runTx((tx) async {
    final id = await ClinicalRepo.registerSource(tx,
        kind: 'drugs', source: prov.source, version: prov.version, url: prov.url);
    var n = 0;
    for (final d in drugs) {
      await DrugRepo.upsert(tx, d, id);
      if (++n % 2000 == 0) stdout.writeln('  $n / ${drugs.length}');
    }
    await ClinicalRepo.finishSource(tx, id, drugs.length, skipped.length);
  });
  await db.close();
  stdout.writeln('İçe aktarma tamamlandı.');
}

class _Table {
  _Table(this.cols, this.rows);
  final Map<String, int> cols;
  final List<(int, List<String>)> rows;

  String? cell(List<String> row, String field) {
    final i = cols[field];
    if (i == null || i >= row.length) return null;
    final s = row[i].trim();
    return s.isEmpty ? null : s;
  }
}

/// Finds the first sheet whose header (within the first 15 rows) maps every
/// required column. Exits with a report if none does.
_Table _table(String path, Map<String, dynamic> cfg) {
  final aliases = (cfg['columns'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as List).cast<String>()));
  final required = (cfg['required'] as List).cast<String>();
  final sheets = readXlsx(File(path).readAsBytesSync());
  for (final s in sheets) {
    for (var r = 0; r < s.rows.length && r < 15; r++) {
      final m = mapHeaders(s.rows[r], aliases);
      if (required.every(m.containsKey)) {
        stdout.writeln('$path: "${s.name}" sayfası, başlık satırı ${r + 1}; sütunlar: ${m.keys.join(', ')}');
        return _Table(m, [for (var i = r + 1; i < s.rows.length; i++) (i + 1, s.rows[i])]);
      }
    }
  }
  stderr.writeln('$path: gerekli sütunlar (${required.join(', ')}) hiçbir sayfada bulunamadı.');
  for (final s in sheets.take(3)) {
    stderr.writeln('  [${s.name}] ${s.rows.take(4).map((r) => r.join(' | ')).join('\n  ')}');
  }
  stderr.writeln('config/titck_columns.json içindeki başlık eşlemelerini güncelleyin.');
  exit(2);
}

/// SKRS: barcode → (rx type, status). Active and passive sheets both count.
Map<String, ({String? rx, MarketStatus status})> _skrsIndex(String path, Map<String, dynamic> cfg) {
  final aliases = (cfg['columns'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as List).cast<String>()));
  final out = <String, ({String? rx, MarketStatus status})>{};
  for (final s in readXlsx(File(path).readAsBytesSync())) {
    for (var r = 0; r < s.rows.length && r < 15; r++) {
      final m = mapHeaders(s.rows[r], aliases);
      if (!m.containsKey('barcode') || !m.containsKey('name')) continue;
      final t = _Table(m, [for (var i = r + 1; i < s.rows.length; i++) (i + 1, s.rows[i])]);
      for (final (_, row) in t.rows) {
        final b = t.cell(row, 'barcode')?.replaceAll(RegExp(r'\D'), '');
        if (b == null || b.isEmpty) continue;
        final st = searchFold(t.cell(row, 'status') ?? '');
        out[b] = (
          rx: t.cell(row, 'rxType'),
          status: st.startsWith('aktif') ? MarketStatus.aktif : st.startsWith('pasif') ? MarketStatus.pasif : MarketStatus.bilinmiyor,
        );
      }
      break;
    }
  }
  stdout.writeln('$path: ${out.length} SKRS kaydı');
  return out;
}
