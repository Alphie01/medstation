import 'package:meta/meta.dart';

/// Parsed GS1 DataMatrix (İTS karekod) content.
@immutable
class Gs1Data {
  const Gs1Data({
    required this.gtin,
    this.serial,
    this.expiry,
    this.lot,
    this.ambiguous = false,
  });

  /// 14-digit GTIN (AI 01).
  final String gtin;
  final String? serial;
  final DateTime? expiry;
  final String? lot;

  /// True when variable-length fields had no FNC1 separator and their
  /// boundaries were inferred. The UI must ask the user to confirm.
  final bool ambiguous;

  /// 13-digit barcode as printed on Turkish packs (GTIN without the leading 0).
  String get barcode => gtin.startsWith('0') ? gtin.substring(1) : gtin;
}

class Gs1FormatException implements Exception {
  Gs1FormatException(this.message);
  final String message;
  @override
  String toString() => 'Gs1FormatException: $message';
}

/// Parses İTS karekod strings and plain EAN-13/GTIN barcodes.
///
/// Accepts raw scanner output with FNC1 as ASCII 29 (GS), the `]d2`
/// symbology prefix, and the human-readable `(01)…(21)…` form.
class Gs1Parser {
  static const _gs = '\u001d';

  static Gs1Data parse(String raw) {
    var s = raw.trim();
    if (s.startsWith(']d2') || s.startsWith(']C1') || s.startsWith(']Q3')) {
      s = s.substring(3);
    }
    if (s.startsWith(_gs)) s = s.substring(1);

    if (RegExp(r'^\d{8}$|^\d{12,14}$').hasMatch(s)) {
      return Gs1Data(gtin: s.padLeft(14, '0'));
    }
    if (s.startsWith('(')) return _parseParens(s);
    return _parseRaw(s);
  }

  static Gs1Data _parseParens(String s) {
    final m = RegExp(r'\((\d{2})\)([^(]*)').allMatches(s);
    final f = {for (final x in m) x.group(1)!: x.group(2)!.trim()};
    return _build(f, ambiguous: false);
  }

  static Gs1Data _parseRaw(String s) {
    final f = <String, String>{};
    var i = 0;
    var ambiguous = false;
    while (i < s.length) {
      if (s[i] == _gs) {
        i++;
        continue;
      }
      if (i + 2 > s.length) throw Gs1FormatException('Eksik AI: "$s"');
      final ai = s.substring(i, i + 2);
      i += 2;
      switch (ai) {
        case '01':
          f[ai] = _take(s, i, 14);
          i += 14;
        case '17':
          f[ai] = _take(s, i, 6);
          i += 6;
        case '10' || '21':
          final gs = s.indexOf(_gs, i);
          var end = gs < 0 ? s.length : gs;
          if (gs < 0) {
            // No separator: look for the next fixed-length AI that would
            // plausibly follow ("17" + valid date, or "01" + 14 digits).
            final next = _guessBoundary(s, i);
            if (next != null) {
              end = next;
              ambiguous = true;
            }
          }
          if (end - i > 20) {
            throw Gs1FormatException('AI $ai 20 karakterden uzun');
          }
          f[ai] = s.substring(i, end);
          i = end;
        default:
          throw Gs1FormatException('Desteklenmeyen AI "$ai"');
      }
    }
    return _build(f, ambiguous: ambiguous);
  }

  static int? _guessBoundary(String s, int from) {
    for (var k = from + 1; k <= s.length - 8; k++) {
      if (s.startsWith('17', k) &&
          _date(s.substring(k + 2, k + 8)) != null &&
          (k + 8 == s.length || s.startsWith('10', k + 8) ||
              s.startsWith('21', k + 8))) {
        return k;
      }
    }
    return null;
  }

  static String _take(String s, int i, int n) {
    if (i + n > s.length) throw Gs1FormatException('Alan kısa: "$s"');
    return s.substring(i, i + n);
  }

  static Gs1Data _build(Map<String, String> f, {required bool ambiguous}) {
    final gtin = f['01'];
    if (gtin == null || !RegExp(r'^\d{14}$').hasMatch(gtin)) {
      throw Gs1FormatException('GTIN (01) bulunamadı');
    }
    if (!isValidGtin(gtin)) {
      throw Gs1FormatException('GTIN kontrol hanesi hatalı');
    }
    final exp = f['17'];
    final date = exp == null ? null : _date(exp);
    if (exp != null && date == null) {
      throw Gs1FormatException('Son kullanma tarihi (17) geçersiz: $exp');
    }
    return Gs1Data(
      gtin: gtin,
      serial: f['21'],
      lot: f['10'],
      expiry: date,
      ambiguous: ambiguous,
    );
  }

  /// YYMMDD; DD=00 means the last day of the month (GS1 spec).
  static DateTime? _date(String v) {
    if (!RegExp(r'^\d{6}$').hasMatch(v)) return null;
    final yy = int.parse(v.substring(0, 2));
    final mm = int.parse(v.substring(2, 4));
    final dd = int.parse(v.substring(4, 6));
    if (mm < 1 || mm > 12) return null;
    // GS1 century rule simplified: 00–49 → 20xx, 50–99 → 19xx.
    final year = yy < 50 ? 2000 + yy : 1900 + yy;
    final last = DateTime(year, mm + 1, 0).day;
    if (dd > last) return null;
    return DateTime(year, mm, dd == 0 ? last : dd);
  }

  static bool isValidGtin(String digits) {
    var sum = 0;
    for (var i = 0; i < digits.length - 1; i++) {
      final d = digits.codeUnitAt(digits.length - 2 - i) - 48;
      sum += i.isEven ? d * 3 : d;
    }
    final check = (10 - sum % 10) % 10;
    return check == digits.codeUnitAt(digits.length - 1) - 48;
  }
}
