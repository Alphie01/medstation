import 'package:medstation_core/medstation_core.dart';
import 'package:postgres/postgres.dart';

import '../db.dart';
import '../repos/clinical_repo.dart';
import '../repos/drug_repo.dart';
import 'titck_parse.dart';
import 'xlsx_reader.dart';

/// One TİTCK file used for an import.
class TitckFile {
  TitckFile({required this.bytes, required this.version, this.url});
  final List<int> bytes;

  /// Publication date as shown by TİTCK, ISO (yyyy-mm-dd).
  final String version;
  final String? url;
}

class ImportReport {
  ImportReport();
  int read = 0;
  int unparsed = 0;
  int withAmount = 0;
  int suspended = 0;
  int badCheck = 0;
  int skrsMatched = 0;
  final skipped = <String>[];
  final samples = <String>[];

  List<String> summary() => [
        'Okunan: $read, atlanan: ${skipped.length}',
        '  bileşimi ayrıştırılamayan (kaynak metin saklandı): $unparsed',
        '  etken madde miktarı atanan (tek etkenli): $withAmount',
        '  ruhsatı askıda: $suspended',
        '  kontrol hanesi hatalı barkod (kaynaktaki gibi alındı): $badCheck',
        '  SKRS ile eşleşen: $skrsMatched',
      ];
}

class ImportFailure implements Exception {
  ImportFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Imports the TİTCK licensed products list (dinamikmodul/85), merged with
/// the SKRS e-prescription list (dinamikmodul/43), into the shared drug table.
///
/// Invalid rows are skipped and reported. Unparseable compositions keep the
/// source text with no ingredients; amounts are attached only to
/// single-ingredient products. Prices are not in these lists.
class TitckImporter {
  TitckImporter(this.columns);

  /// Contents of config/titck_columns.json.
  final Map<String, dynamic> columns;

  ({List<Drug> drugs, ImportReport report}) parse(TitckFile ruhsatli, TitckFile? skrs) {
    final table = _table(ruhsatli.bytes, columns['ruhsatli'] as Map<String, dynamic>, 'Ruhsatlı ürünler listesi');
    final skrsIdx = skrs == null ? null : _skrsIndex(skrs.bytes, columns['skrs'] as Map<String, dynamic>);
    final prov = provenance(ruhsatli, skrs);
    final rep = ImportReport();
    final drugs = <Drug>[];
    final seen = <String>{};
    for (final (rowNo, row) in table.rows) {
      String? c(String f) => table.cell(row, f);
      final barcode = c('barcode')?.replaceAll(RegExp(r'\D'), '');
      final name = c('name');
      final ingCell = c('ingredients');
      if (barcode == null && name == null) continue;
      if (barcode == null || !RegExp(r'^\d{8,14}$').hasMatch(barcode)) {
        rep.skipped.add('Satır $rowNo: geçersiz barkod "${c('barcode')}"');
        continue;
      }
      // Some published barcodes fail the GS1 check digit. They are imported as
      // published (name search still finds them) and reported; a scanned
      // karekod can never match them.
      if (!Gs1Parser.isValidGtin(barcode.padLeft(14, '0'))) rep.badCheck++;
      if (name == null) {
        rep.skipped.add('Satır $rowNo: ürün adı boş');
        continue;
      }
      if (!seen.add(barcode)) {
        rep.skipped.add('Satır $rowNo: tekrar eden barkod $barcode');
        continue;
      }
      final parsed = ingCell == null ? (ingredients: const <DrugIngredient>[], raw: null) : ingredientsFrom(ingCell, name);
      if (parsed.ingredients.isEmpty) rep.unparsed++;
      if (parsed.ingredients.any((i) => i.amount != null)) rep.withAmount++;
      final lic = LicenseStatus.fromCode(int.tryParse(c('license') ?? ''));
      if (lic.suspended) rep.suspended++;
      final s = skrsIdx?[barcode];
      if (s != null) rep.skrsMatched++;
      final d = Drug(
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
      );
      if (d.ingredients.length > 1 && rep.samples.length < 3) {
        rep.samples.add('${d.name} → ${d.ingredients.map((i) => i.name).join(' | ')} [${d.rxType.name}, ${d.marketStatus.name}]');
      }
      drugs.add(d);
    }
    rep.read = drugs.length;
    if (drugs.length < 1000) {
      // A real list has ~23k products; a tiny result means the file or its
      // layout changed. Keep the current data rather than replacing it.
      throw ImportFailure('Yalnızca ${drugs.length} ürün okundu; dosya yapısı değişmiş olabilir. Mevcut veri korunuyor.');
    }
    return (drugs: drugs, report: rep);
  }

  static DataProvenance provenance(TitckFile ruhsatli, TitckFile? skrs) => DataProvenance(
        source: skrs == null ? 'TİTCK Ruhsatlı Beşeri Tıbbi Ürünler Listesi' : 'TİTCK Ruhsatlı Ürünler + SKRS E-Reçete Listesi',
        version: skrs == null ? ruhsatli.version : '${ruhsatli.version} / SKRS ${skrs.version}',
        url: 'https://www.titck.gov.tr/dinamikmodul/85',
        fetchedAt: DateTime.now().toUtc(),
      );

  /// Parses and writes in one transaction; the previous list stays active
  /// until the new one is fully written.
  Future<ImportReport> run(Db db, TitckFile ruhsatli, TitckFile? skrs, {void Function(String)? log}) async {
    final (:drugs, :report) = parse(ruhsatli, skrs);
    final prov = provenance(ruhsatli, skrs);
    await db.runTx((tx) async {
      final id = await ClinicalRepo.registerSource(tx,
          kind: 'drugs', source: prov.source, version: prov.version, url: prov.url);
      await tx.execute(Sql.named('UPDATE data_sources SET meta = @m WHERE id = @id'), parameters: {
        'id': id,
        'm': TypedValue(Type.jsonb, {
          'ruhsatliVersion': ruhsatli.version,
          'ruhsatliUrl': ruhsatli.url,
          'skrsVersion': skrs?.version,
          'skrsUrl': skrs?.url,
        }),
      });
      var n = 0;
      for (final d in drugs) {
        await DrugRepo.upsert(tx, d, id);
        if (++n % 5000 == 0) log?.call('  $n / ${drugs.length}');
      }
      await ClinicalRepo.finishSource(tx, id, drugs.length, report.skipped.length);
    });
    return report;
  }
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

Map<String, List<String>> _aliases(Map<String, dynamic> cfg) =>
    (cfg['columns'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as List).cast<String>()));

/// First sheet whose header (within the first 15 rows) maps every required
/// column.
_Table _table(List<int> bytes, Map<String, dynamic> cfg, String label) {
  final aliases = _aliases(cfg);
  final required = (cfg['required'] as List).cast<String>();
  final sheets = readXlsx(bytes);
  for (final s in sheets) {
    for (var r = 0; r < s.rows.length && r < 15; r++) {
      final m = mapHeaders(s.rows[r], aliases);
      if (required.every(m.containsKey)) {
        return _Table(m, [for (var i = r + 1; i < s.rows.length; i++) (i + 1, s.rows[i])]);
      }
    }
  }
  final preview = sheets.take(2).map((s) => '[${s.name}] ${s.rows.take(3).map((r) => r.join(' | ')).join(' / ')}').join('\n');
  throw ImportFailure('$label: gerekli sütunlar (${required.join(', ')}) bulunamadı. '
      'config/titck_columns.json eşlemelerini güncelleyin.\n$preview');
}

/// SKRS: barcode → (rx type, status). Active and passive sheets both count.
Map<String, ({String? rx, MarketStatus status})> _skrsIndex(List<int> bytes, Map<String, dynamic> cfg) {
  final aliases = _aliases(cfg);
  final out = <String, ({String? rx, MarketStatus status})>{};
  for (final s in readXlsx(bytes)) {
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
          status: st.startsWith('aktif')
              ? MarketStatus.aktif
              : st.startsWith('pasif')
                  ? MarketStatus.pasif
                  : MarketStatus.bilinmiyor,
        );
      }
      break;
    }
  }
  return out;
}
