import 'package:medstation_core/medstation_core.dart';
import 'package:postgres/postgres.dart';

import '../db.dart';

const _drugCols = '''
  d.id, d.barcode, d.name, d.firm, d.form, d.strength, d.pack, d.atc,
  d.rx_type, d.sgk_status, d.psf, d.equivalence_code, d.storage, d.kub_url,
  d.kt_url, d.composition_text, d.market_status, d.license_status,
  d.recalled OR EXISTS (SELECT 1 FROM recalls r WHERE r.barcode = d.barcode) AS recalled,
  s.source AS s_source, s.version AS s_version, s.url AS s_url,
  s.fetched_at AS s_fetched_at, s.is_sample AS s_is_sample
''';

const _from = 'FROM drugs d JOIN data_sources s ON s.id = d.source_id AND s.active';

DataProvenance provenanceFromRow(Map<String, dynamic> m, [String p = 's_']) =>
    DataProvenance(
      source: m['${p}source'] as String,
      version: m['${p}version'] as String,
      url: m['${p}url'] as String?,
      fetchedAt: m['${p}fetched_at'] as DateTime,
      isSample: m['${p}is_sample'] as bool,
    );

double? _num(Object? v) => switch (v) {
      null => null,
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => double.tryParse(v.toString()),
    };

class SearchResult {
  SearchResult(this.items, this.inclCount, this.exactCount, this.formCounts);
  final List<Drug> items;
  final int inclCount;
  final int exactCount;
  final Map<String, int> formCounts;
}

class DrugRepo {
  DrugRepo(this.db);
  final Db db;

  Future<List<Drug>> _load(String where, Map<String, dynamic> params,
      {String order = 'd.name', int limit = 200}) async {
    final rows = await db.execute(
      Sql.named('SELECT $_drugCols $_from WHERE $where ORDER BY $order LIMIT $limit'),
      parameters: params,
    );
    if (rows.isEmpty) return const [];
    final maps = rows.map((r) => r.toColumnMap()).toList();
    final ids = maps.map((m) => m['id'] as String).toList();
    final ingRows = await db.execute(
      Sql.named('SELECT drug_id, name, amount, unit, per_volume_ml FROM drug_ingredients '
          'WHERE drug_id = ANY(@ids:_text) ORDER BY drug_id, position'),
      parameters: {'ids': ids},
    );
    final ings = <String, List<DrugIngredient>>{};
    for (final r in ingRows) {
      final m = r.toColumnMap();
      ings.putIfAbsent(m['drug_id'] as String, () => []).add(DrugIngredient(
            name: m['name'] as String,
            amount: _num(m['amount']),
            unit: m['unit'] as String?,
            perVolumeMl: _num(m['per_volume_ml']),
          ));
    }
    return [
      for (final m in maps)
        Drug(
          id: m['id'] as String,
          barcode: m['barcode'] as String?,
          name: m['name'] as String,
          firm: m['firm'] as String?,
          form: m['form'] as String?,
          strength: m['strength'] as String?,
          pack: m['pack'] as String?,
          atc: m['atc'] as String?,
          rxType: RxType.parse(m['rx_type'] as String?),
          sgkStatus: m['sgk_status'] as String?,
          psf: _num(m['psf']),
          equivalenceCode: m['equivalence_code'] as String?,
          storage: m['storage'] as String?,
          kubUrl: m['kub_url'] as String?,
          ktUrl: m['kt_url'] as String?,
          recalled: m['recalled'] as bool,
          compositionText: m['composition_text'] as String?,
          marketStatus: MarketStatus.parse(m['market_status'] as String?),
          licenseStatus: LicenseStatus.fromCode(m['license_status'] as int?),
          ingredients: ings[m['id']] ?? const [],
          provenance: provenanceFromRow(m),
        ),
    ];
  }

  Future<Drug?> byId(String id) async =>
      (await _load('d.id = @id', {'id': id})).firstOrNull;

  Future<Drug?> byBarcode(String barcode) async =>
      (await _load('d.barcode = @b', {'b': barcode})).firstOrNull;

  Future<List<Drug>> byIds(List<String> ids) =>
      _load('d.id = ANY(@ids:_text)', {'ids': ids}, limit: 500);

  static String _ingFilter(bool exact) => '''
    d.id IN (
      SELECT drug_id FROM drug_ingredients GROUP BY drug_id
      HAVING count(DISTINCT base_key) FILTER (WHERE base_key = ANY(@keys:_text)) = cardinality(@keys:_text)
      ${exact ? 'AND count(DISTINCT base_key) = cardinality(@keys:_text)' : ''}
    )''';

  /// Free-text (name/barcode) and/or ingredient search, as on the reference
  /// Arama → Sonuçlar flow.
  Future<SearchResult> search({
    String? text,
    List<String> ingredients = const [],
    MatchMode mode = MatchMode.incl,
    FormGroup? form,
    int limit = 200,
  }) async {
    final keys = ingredients.map(baseIngredient).toSet().toList();
    final conds = <String>[];
    final p = <String, dynamic>{};
    if (text != null) {
      conds.add("(d.name_fold LIKE '%' || @t || '%' OR d.barcode = @raw)");
      p['t'] = searchFold(text);
      p['raw'] = text.trim();
    }
    if (keys.isNotEmpty) p['keys'] = keys;
    if (conds.isEmpty && keys.isEmpty) return SearchResult(const [], 0, 0, const {});

    final base = conds.isEmpty ? 'true' : conds.join(' AND ');
    var inclCount = 0, exactCount = 0;
    var formCounts = <String, int>{};
    String where;
    if (keys.isEmpty) {
      where = base;
    } else {
      final counts = await db.execute(
        Sql.named('SELECT '
            '(SELECT count(*) $_from WHERE $base AND ${_ingFilter(false)}), '
            '(SELECT count(*) $_from WHERE $base AND ${_ingFilter(true)})'),
        parameters: p,
      );
      inclCount = counts.first[0] as int;
      exactCount = counts.first[1] as int;
      where = '$base AND ${_ingFilter(mode == MatchMode.exact)}';
    }
    final fc = await db.execute(
      Sql.named('SELECT d.form_group, count(*) $_from WHERE $where GROUP BY d.form_group'),
      parameters: p,
    );
    formCounts = {for (final r in fc) r[0] as String: r[1] as int};

    var w = where;
    if (form != null) {
      w = '$where AND d.form_group = @fg';
      p['fg'] = form.name;
    }
    final items = await _load(w, p,
        order: text != null ? "d.name_fold LIKE @t || '%' DESC, d.name" : 'd.name',
        limit: limit);
    if (keys.isEmpty) inclCount = exactCount = items.length;
    return SearchResult(items, inclCount, exactCount, formCounts);
  }

  /// Interchangeable products: same TİTCK equivalence code when present,
  /// otherwise same ingredient set/amounts/form group (core grouping).
  Future<List<Drug>> equivalents(Drug d) async {
    final keys = d.ingredients.map((i) => baseIngredient(i.name)).toSet().toList();
    if (keys.isEmpty) return const [];
    final candidates = await _load(
      '${_ingFilter(true)} AND d.id <> @id',
      {'keys': keys, 'id': d.id},
      limit: 500,
    );
    return equivalentsOf(d, candidates);
  }

  Future<List<Map<String, dynamic>>> suggestIngredients(String query) async {
    final f = searchFold(query);
    final r = await db.execute(
      Sql.named('''
        SELECT i.base_key, count(DISTINCT i.drug_id) AS n, bool_or(i.fold LIKE @q || '%') AS prefix
        FROM drug_ingredients i JOIN drugs d ON d.id = i.drug_id
        JOIN data_sources s ON s.id = d.source_id AND s.active
        WHERE i.fold LIKE '%' || @q || '%'
        GROUP BY i.base_key ORDER BY prefix DESC, n DESC LIMIT 8'''),
      parameters: {'q': f},
    );
    return [for (final x in r) {'name': x[0], 'productCount': x[1]}];
  }

  Future<List<Map<String, dynamic>>> topIngredients({int limit = 8}) async {
    final r = await db.execute(Sql.named('''
        SELECT i.base_key, count(DISTINCT i.drug_id) AS n
        FROM drug_ingredients i JOIN drugs d ON d.id = i.drug_id
        JOIN data_sources s ON s.id = d.source_id AND s.active
        GROUP BY i.base_key ORDER BY n DESC LIMIT @l'''), parameters: {'l': limit});
    return [for (final x in r) {'name': x[0], 'productCount': x[1]}];
  }

  /// Upserts a drug and its ingredients (used by ingest jobs).
  static Future<void> upsert(TxSession tx, Drug d, int sourceId) async {
    await tx.execute(
      Sql.named('''
        INSERT INTO drugs (id, barcode, name, name_fold, firm, form, form_group, strength, pack,
          atc, rx_type, sgk_status, psf, equivalence_code, storage, kub_url, kt_url, recalled, source_id,
          composition_text, market_status, license_status)
        VALUES (@id, @barcode, @name, @fold, @firm, @form, @fg, @strength, @pack, @atc, @rx, @sgk,
          @psf, @eq, @storage, @kub, @kt, @recalled, @src, @comp, @market, @license)
        ON CONFLICT (id) DO UPDATE SET barcode = EXCLUDED.barcode, name = EXCLUDED.name,
          name_fold = EXCLUDED.name_fold, firm = EXCLUDED.firm, form = EXCLUDED.form,
          form_group = EXCLUDED.form_group, strength = EXCLUDED.strength, pack = EXCLUDED.pack,
          atc = EXCLUDED.atc, rx_type = EXCLUDED.rx_type, sgk_status = EXCLUDED.sgk_status,
          psf = EXCLUDED.psf, equivalence_code = EXCLUDED.equivalence_code,
          storage = COALESCE(EXCLUDED.storage, drugs.storage),
          kub_url = COALESCE(EXCLUDED.kub_url, drugs.kub_url),
          kt_url = COALESCE(EXCLUDED.kt_url, drugs.kt_url),
          recalled = EXCLUDED.recalled, source_id = EXCLUDED.source_id,
          composition_text = EXCLUDED.composition_text, market_status = EXCLUDED.market_status,
          license_status = EXCLUDED.license_status'''),
      parameters: {
        'id': d.id,
        'barcode': d.barcode,
        'name': d.name,
        'fold': searchFold(d.name),
        'firm': d.firm,
        'form': d.form,
        'fg': d.formGroup.name,
        'strength': d.strength,
        'pack': d.pack,
        'atc': d.atc,
        'rx': d.rxType.name,
        'sgk': d.sgkStatus,
        'psf': d.psf == null ? null : TypedValue(Type.numeric, d.psf.toString()),
        'eq': d.equivalenceCode,
        'storage': d.storage,
        'kub': d.kubUrl,
        'kt': d.ktUrl,
        'recalled': d.recalled,
        'src': sourceId,
        'comp': d.compositionText,
        'market': d.marketStatus.name,
        'license': d.licenseStatus.code,
      },
    );
    await tx.execute(Sql.named('DELETE FROM drug_ingredients WHERE drug_id = @id'),
        parameters: {'id': d.id});
    for (var i = 0; i < d.ingredients.length; i++) {
      final ing = d.ingredients[i];
      final base = baseIngredient(ing.name);
      await tx.execute(
        Sql.named('INSERT INTO drug_ingredients (drug_id, position, name, base_key, fold, '
            'amount, unit, per_volume_ml) VALUES (@d, @p, @n, @b, @f, @a, @u, @v)'),
        parameters: {
          'd': d.id,
          'p': i,
          'n': ing.name,
          'b': base,
          'f': searchFold(base),
          'a': ing.amount,
          'u': ing.unit,
          'v': ing.perVolumeMl,
        },
      );
    }
  }
}
