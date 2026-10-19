/// Removes direct identifiers before any text leaves our infrastructure
/// (KVKK). This is a defence-in-depth filter; the app also avoids collecting
/// identities in the first place.
String redactPii(String input) {
  var s = input;
  // T.C. kimlik no: 11 digits, first non-zero.
  s = s.replaceAll(RegExp(r'\b[1-9]\d{10}\b'), '[TCKN]');
  // Phone numbers (+90 / 0 5xx …).
  s = s.replaceAll(
      RegExp(r'(\+?90[\s-]?)?0?5\d{2}[\s-]?\d{3}[\s-]?\d{2}[\s-]?\d{2}\b'), '[TELEFON]');
  s = s.replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'), '[E-POSTA]');
  // e-Reçete numbers are alphanumeric 7-char codes; strip when labelled.
  s = s.replaceAll(
      RegExp(r'(reçete\s*(no|numarası|kodu)\s*[:#]?\s*)[A-Z0-9]{5,10}', caseSensitive: false),
      r'$1[REÇETE]');
  // "Hasta: Ad Soyad" / "hastam Ayşe Yılmaz" style names after a label.
  s = s.replaceAllMapped(
      RegExp(r'([Hh]asta(m|nın|nin)?\s*(adı)?\s*[:]?\s+)([A-ZÇĞİÖŞÜ][a-zçğıöşü]+(\s+[A-ZÇĞİÖŞÜ][a-zçğıöşü]+){0,2})'),
      (m) => '${m[1]}[İSİM]');
  return s;
}
