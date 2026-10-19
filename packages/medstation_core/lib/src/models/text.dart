/// Turkish-aware lower-casing and normalisation for ingredient matching.
///
/// Dart's [String.toLowerCase] maps `I` to `i`, which is wrong for Turkish
/// (`I` → `ı`, `İ` → `i`). Ingredient names in TİTCK lists are mostly upper
/// case, so this matters for matching.
String trLower(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    switch (r) {
      case 0x49: // I
        b.write('ı');
      case 0x130: // İ
        b.write('i');
      default:
        b.write(String.fromCharCode(r).toLowerCase());
    }
  }
  return b.toString();
}

/// Key used to compare ingredient names: lower case, single spaces, and
/// common salt/hydrate suffixes kept (they matter for dosing) but punctuation
/// collapsed.
String ingredientKey(String name) => trLower(name)
    .replaceAll(RegExp(r'[\s\-_/,.;:()]+'), ' ')
    .trim();

/// Folds Turkish letters to ASCII for fuzzy search ("amoksisilin" vs
/// "AMOKSİSİLİN", "sefuroksim" vs "sefüroksim").
String searchFold(String s) => trLower(s)
    .replaceAll('ı', 'i')
    .replaceAll('ş', 's')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

const _saltWords = {
  'trihidrat', 'dihidrat', 'monohidrat', 'hemihidrat', 'seskihidrat',
  'hidrat', 'anhidr', 'anhidrus', 'hidroklorur', 'hidroklorür', 'hcl', 'hidrobromur',
  'hidrobromür', 'hbr', 'hci', 'maleat', 'besilat', 'mesilat', 'fumarat', 'suksinat',
  'tartarat', 'sitrat', 'fosfat', 'sulfat', 'sülfat', 'asetat', 'laktat',
  'klorur', 'klorür', 'bromur', 'bromür', 'tosilat', 'oksalat', 'nitrat',
  'propionat', 'dipropionat', 'valerat', 'furoat', 'pivoksil', 'aksetil',
  'medoksomil', 'sileksetil', 'trometamol', 'arjinin', 'lizin',
};

/// Cations are only dropped when they follow the moiety ("amoksisilin
/// sodyum"); as the first word they are the active part ("kalsiyum karbonat").
const _cationWords = {'sodyum', 'potasyum', 'kalsiyum', 'magnezyum'};

/// Ingredient with salt/ester/hydrate words removed, used to detect the same
/// therapeutic moiety across products ("amoksisilin trihidrat" and
/// "amoksisilin sodyum" → "amoksisilin"; "metformin HCl" → "metformin").
///
/// Only a fixed word list is removed. If nothing is left the original key is
/// returned unchanged, so unknown names are never collapsed by guessing.
String baseIngredient(String name) {
  final key = ingredientKey(name);
  final words = key.split(' ');
  final kept = [
    for (var i = 0; i < words.length; i++)
      if (!_saltWords.contains(words[i]) &&
          !(i > 0 && _cationWords.contains(words[i])))
        words[i],
  ];
  return kept.isEmpty ? key : kept.join(' ');
}
