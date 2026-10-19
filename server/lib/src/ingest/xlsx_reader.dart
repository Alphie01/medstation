import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Minimal .xlsx reader: cell values only, styles ignored.
///
/// TİTCK files use number formats some Excel libraries reject; reading the
/// sheet XML directly avoids that and keeps memory use predictable.
class XlsxSheet {
  XlsxSheet(this.name, this.rows);
  final String name;

  /// Rows as lists of cell text (empty string for blank cells).
  final List<List<String>> rows;
}

List<XlsxSheet> readXlsx(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String utf8Text(String path) {
    final f = zip.findFile(path);
    if (f == null) throw FormatException('xlsx içinde $path yok');
    return utf8.decode(f.content as List<int>);
  }

  final shared = <String>[];
  if (zip.findFile('xl/sharedStrings.xml') != null) {
    final doc = XmlDocument.parse(utf8Text('xl/sharedStrings.xml'));
    for (final si in doc.findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }

  final wb = XmlDocument.parse(utf8Text('xl/workbook.xml'));
  final rels = XmlDocument.parse(utf8Text('xl/_rels/workbook.xml.rels'));
  final target = {
    for (final r in rels.findAllElements('Relationship')) r.getAttribute('Id')!: r.getAttribute('Target')!,
  };
  final out = <XlsxSheet>[];
  for (final s in wb.findAllElements('sheet')) {
    final rid = s.getAttribute('r:id') ?? s.attributes.firstWhere((a) => a.name.local == 'id').value;
    var path = target[rid]!;
    path = path.startsWith('/') ? path.substring(1) : 'xl/$path';
    if (zip.findFile(path) == null) continue;
    final doc = XmlDocument.parse(utf8Text(path));
    final rows = <List<String>>[];
    for (final row in doc.findAllElements('row')) {
      final cells = <String>[];
      for (final c in row.findElements('c')) {
        final col = _colIndex(c.getAttribute('r'));
        while (col != null && cells.length < col) {
          cells.add('');
        }
        final type = c.getAttribute('t');
        final v = c.getElement('v')?.innerText;
        String value;
        if (type == 's' && v != null) {
          value = shared[int.parse(v)];
        } else if (type == 'inlineStr') {
          value = c.findAllElements('t').map((t) => t.innerText).join();
        } else {
          value = v ?? '';
        }
        cells.add(value.trim());
      }
      rows.add(cells);
    }
    out.add(XlsxSheet(s.getAttribute('name') ?? 'Sheet', rows));
  }
  return out;
}

int? _colIndex(String? ref) {
  if (ref == null) return null;
  var n = 0;
  for (final ch in ref.codeUnits) {
    if (ch < 65 || ch > 90) break;
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}
