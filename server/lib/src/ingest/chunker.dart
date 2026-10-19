/// Splits KÜB/KT text into section-aware chunks for retrieval.
///
/// KÜB texts use numbered headings ("4.2 Pozoloji ve uygulama şekli"); each
/// chunk keeps its heading so citations can name the section.
class TextChunk {
  TextChunk(this.section, this.text);
  final String? section;
  final String text;
}

final _heading = RegExp(r'^\s*(\d{1,2}(?:\.\d{1,2}){0,2})\.?\s+([A-ZÇĞİÖŞÜa-zçğıöşü].{2,90})$');

List<TextChunk> chunkDocument(String text, {int maxChars = 1500}) {
  final out = <TextChunk>[];
  String? section;
  final buf = StringBuffer();
  void flush() {
    final t = buf.toString().trim();
    buf.clear();
    if (t.isEmpty) return;
    if (t.length <= maxChars) {
      out.add(TextChunk(section, t));
      return;
    }
    // Long section: split on paragraph boundaries.
    final paras = t.split(RegExp(r'\n\s*\n'));
    final b = StringBuffer();
    for (final p in paras) {
      if (b.length + p.length > maxChars && b.isNotEmpty) {
        out.add(TextChunk(section, b.toString().trim()));
        b.clear();
      }
      if (p.length > maxChars) {
        for (var i = 0; i < p.length; i += maxChars) {
          out.add(TextChunk(section, p.substring(i, (i + maxChars).clamp(0, p.length)).trim()));
        }
      } else {
        b.writeln(p);
        b.writeln();
      }
    }
    if (b.isNotEmpty) out.add(TextChunk(section, b.toString().trim()));
  }

  for (final line in text.replaceAll('\r', '').split('\n')) {
    final m = _heading.firstMatch(line);
    if (m != null) {
      flush();
      section = '${m[1]} ${m[2]!.trim()}';
      continue;
    }
    buf.writeln(line);
  }
  flush();
  return out;
}
