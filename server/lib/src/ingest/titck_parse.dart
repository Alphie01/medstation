import 'package:medstation_core/medstation_core.dart';

/// Maps header names to field names using the alias config. An alias ending
/// in `*` matches any header that starts with it (TİTCK puts code legends
/// inside some header cells).
Map<String, int> mapHeaders(List<String> headers, Map<String, List<String>> aliases) {
  final folded = [for (final h in headers) searchFold(h.replaceAll('\n', ' '))];
  final out = <String, int>{};
  aliases.forEach((field, names) {
    for (final n in names) {
      final prefix = n.endsWith('*');
      final key = searchFold(prefix ? n.substring(0, n.length - 1) : n);
      final i = folded.indexWhere((h) => prefix ? h.startsWith(key) : h == key);
      if (i >= 0) {
        out[field] = i;
        break;
      }
    }
  });
  return out;
}

const _forms = [
  'film kapli tablet', 'efervesan tablet', 'cigneme tableti', 'agizda dagilan tablet',
  'kontrollu salimli tablet', 'uzatilmis salimli tablet', 'tablet', 'sert kapsul',
  'yumusak kapsul', 'kapsul', 'oral suspansiyon icin toz', 'oral suspansiyon',
  'surup', 'goz damlasi', 'damla', 'oral cozelti', 'sase', 'enjeksiyonluk cozelti',
  'infuzyonluk cozelti', 'infuzyon icin cozelti', 'ampul', 'flakon', 'krem', 'merhem',
  'jel', 'pomad', 'sprey', 'supozituvar', 'losyon', 'inhaler', 'poset',
];

/// Dosage form from a product name, or null if not recognised.
String? formFromName(String name) {
  final f = searchFold(name);
  for (final k in _forms) {
    if (f.contains(k)) return k;
  }
  return null;
}

final _amountRe = RegExp(r'(\d+(?:[.,]\d+)?)\s*(mg|mcg|µg|g|iu|ui)\b', caseSensitive: false);
final _perMlRe = RegExp(r'^\s*/\s*(\d+(?:[.,]\d+)?)?\s*ml\b', caseSensitive: false);

double _d(String s) => double.parse(s.replaceAll(',', '.'));

class ParsedStrength {
  ParsedStrength(this.label, this.amounts, this.units, this.perMl);

  /// Strength text as printed in the name, e.g. "875 MG/125 MG".
  final String label;
  final List<double> amounts;
  final List<String> units;
  final double? perMl;
}

/// Strength expression in a product name. Amount order in combination
/// names does not reliably follow the ingredient order, so callers only
/// attach amounts to single-ingredient products.
ParsedStrength? strengthFromName(String name) {
  final ms = _amountRe.allMatches(name).toList();
  if (ms.isEmpty) return null;
  // Use the first contiguous run of amounts ("300 MG/2 MG/10 MG", "1 MG +160 MG").
  final run = <RegExpMatch>[ms.first];
  for (final m in ms.skip(1)) {
    final gap = name.substring(run.last.end, m.start);
    if (RegExp(r'^\s*[/+]\s*$').hasMatch(gap)) {
      run.add(m);
    } else {
      break;
    }
  }
  final tail = name.substring(run.last.end);
  final per = _perMlRe.firstMatch(tail);
  final perMl = per == null ? null : (per.group(1) == null ? 1.0 : _d(per.group(1)!));
  final end = run.last.end + (per?.end ?? 0);
  String unit(String u) => u.toLowerCase().replaceAll('µg', 'mcg').replaceAll('ui', 'iu');
  return ParsedStrength(
    name.substring(run.first.start, end).trim(),
    [for (final m in run) _d(m.group(1)!)],
    [for (final m in run) unit(m.group(2)!)],
    perMl,
  );
}

/// Pack size from the name: "…, 100 TABLET" or "… (30 ADET)".
String? packFromName(String name) {
  final paren = RegExp(r'\(([^()]*\d[^()]*)\)\s*$').firstMatch(name);
  if (paren != null) return paren.group(1)!.trim();
  final i = name.lastIndexOf(',');
  if (i > 0) {
    final t = name.substring(i + 1).trim();
    if (RegExp(r'\d').hasMatch(t) && t.length <= 40) return t;
  }
  return null;
}

/// Phrases that mark an ATC group description rather than an ingredient list.
final _atcPhrase = RegExp(r'combination|excl\.|other drugs|derivative|various|plain|in combination', caseSensitive: false);

final _innerSalt = RegExp(
    r'\b(hidroklorur|hcl|hci|maleat|hidrobromur|hbr|fosfat|sulfat|sitrat|tartarat|mesilat|besilat|fumarat|suksinat)\s+'
    r'(?!(?:hemi|mono|di|tri|tetra|penta|heksa|hekza|hepta|dodeka|seski)?hidrat|anhidr|susuz|dibazik|monobazik|tribazik)'
    r'[a-z]{3,}');

/// Splits a TİTCK "ETKİN MADDE" cell into ingredient names.
///
/// Returns null when the text cannot be split safely (ATC phrases, vaccine
/// strain descriptions, multi-line or very long text); the caller then keeps
/// the raw text and leaves ingredients empty instead of guessing.
List<String>? splitIngredients(String cell) {
  final t = cell.trim();
  if (t.isEmpty) return null;
  if (t.contains('\n') || t.contains(';') || t.length > 160 || _atcPhrase.hasMatch(t)) return null;
  // Mask separators inside parentheses, split at top level, then restore.
  final masked = StringBuffer();
  var depth = 0;
  for (final ch in t.split('')) {
    if (ch == '(') depth++;
    if (ch == ')' && depth > 0) depth--;
    masked.write(depth > 0 && (ch == ',' || ch == '+' || ch == '/') ? (ch == ',' ? '\u0001' : ch == '+' ? '\u0002' : '\u0003') : ch);
  }
  final parts = masked
      .toString()
      .split(RegExp(r'\s*(?:,|\+|/|\s+ve\s+|\s+and\s+)\s*'))
      .map((p) => p.replaceAll('\u0001', ',').replaceAll('\u0002', '+').replaceAll('\u0003', '/').trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty || parts.any((p) => p.length < 2 || p.length > 80)) return null;
  // A salt word followed by more words means several ingredients were run
  // together without a separator ("parasetamol klorfeniramin maleat fenilefrin
  // hcl"); such text cannot be split safely.
  if (parts.any((p) => _innerSalt.hasMatch(searchFold(p)))) return null;
  return parts;
}

/// Ingredients for a product. Amounts are attached only for single-ingredient
/// products whose name has exactly one strength.
({List<DrugIngredient> ingredients, String? raw}) ingredientsFrom(String cell, String productName) {
  final names = splitIngredients(cell);
  if (names == null) return (ingredients: const <DrugIngredient>[], raw: cell.trim());
  final st = strengthFromName(productName);
  final single = names.length == 1 && st != null && st.amounts.length == 1;
  return (
    ingredients: [
      for (final n in names)
        DrugIngredient(
          name: trLower(n),
          amount: single ? st.amounts.single : null,
          unit: single ? st.units.single : null,
          perVolumeMl: single ? st.perMl : null,
        ),
    ],
    raw: cell.trim(),
  );
}

RxType rxFrom(String? v) {
  if (v == null) return RxType.bilinmiyor;
  final f = searchFold(v);
  if (f.contains('kirmizi')) return RxType.kirmizi;
  if (f.contains('yesil')) return RxType.yesil;
  if (f.contains('mor')) return RxType.mor;
  if (f.contains('turuncu')) return RxType.turuncu;
  if (f.contains('recetesiz') || f == 'otc') return RxType.receteSiz;
  if (f.contains('normal') || f.contains('beyaz')) return RxType.normal;
  return RxType.bilinmiyor;
}

double? priceFrom(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  var s = v.toString().trim().replaceAll(RegExp(r'[^\d,.\-]'), '');
  if (s.isEmpty) return null;
  // Turkish format 1.234,56 → 1234.56
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(s);
}
