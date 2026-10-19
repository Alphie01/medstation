import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;

/// Downloads approved KÜB/KT PDFs from TİTCK's public KÜB/KT search
/// (https://www.titck.gov.tr/kubkt), converts them to text with `pdftotext`
/// and writes a manifest for `bin/ingest_documents.dart`.
///
///   dart run bin/fetch_kubkt.dart --out kub --query "PAROL 500 MG TABLET" --query "AUGMENTIN BID 1000"
///
/// Only exact search hits are used; the product name in the manifest is the
/// one TİTCK lists for the document.
Future<void> main(List<String> args) async {
  final p = ArgParser()
    ..addOption('out', mandatory: true)
    ..addMultiOption('query', help: 'Ürün adı (TİTCK KÜB/KT aramasındaki gibi)')
    ..addOption('per-query', defaultsTo: '1');
  final a = p.parse(args);
  final out = Directory(a['out'] as String)..createSync(recursive: true);
  final ua = {'user-agent': 'MedStationBot/0.1 (+eczane bilgi sistemi)'};

  final page = await http.get(Uri.parse('https://www.titck.gov.tr/kubkt'), headers: ua);
  final cookie = (page.headers['set-cookie'] ?? '')
      .split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'))
      .map((c) => c.split(';').first.trim())
      .where((c) => c.isNotEmpty)
      .join('; ');
  final token = RegExp(r'_token: "([^"]+)"').firstMatch(page.body)?.group(1);
  if (token == null) {
    stderr.writeln('KÜB/KT sayfasında oturum anahtarı bulunamadı; sayfa yapısı değişmiş olabilir.');
    exit(2);
  }

  const cols = ['name', 'element', 'firmName', 'confirmationDateKub', 'confirmationDateKt', 'documentPathKub', 'documentPathKt'];
  final manifest = <Map<String, dynamic>>[];
  for (final q in (a['query'] as List<String>)) {
    final body = <String, String>{
      '_token': token,
      'draw': '1',
      'start': '0',
      'length': a['per-query'] as String,
      'search[value]': q,
      'search[regex]': 'false',
      'order[0][column]': '0',
      'order[0][dir]': 'asc',
      for (var i = 0; i < cols.length; i++) ...{
        'columns[$i][data]': cols[i],
        'columns[$i][name]': '',
        'columns[$i][searchable]': 'true',
        'columns[$i][orderable]': 'true',
        'columns[$i][search][value]': '',
        'columns[$i][search][regex]': 'false',
      },
    };
    final res = await http.post(Uri.parse('https://www.titck.gov.tr/getkubktviewdatatable'),
        headers: {...ua, 'cookie': cookie, 'x-requested-with': 'XMLHttpRequest', 'referer': 'https://www.titck.gov.tr/kubkt'},
        body: body);
    final data = (jsonDecode(res.body) as Map<String, dynamic>)['data'] as List? ?? const [];
    if (data.isEmpty) {
      stdout.writeln('Bulunamadı: $q');
      continue;
    }
    for (final row in data.cast<Map<String, dynamic>>()) {
      final name = '${row['name']}'.trim();
      for (final (doc, key, dateKey) in const [('KÜB', 'documentPathKub', 'confirmationDateKub'), ('KT', 'documentPathKt', 'confirmationDateKt')]) {
        final href = RegExp(r'href="([^"]+\.pdf[^"]*)"').firstMatch('${row[key]}')?.group(1);
        if (href == null) continue;
        final url = Uri.parse(href).toString();
        final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
        final pdf = File('${out.path}/$slug-$doc.pdf');
        final dl = await http.get(Uri.parse(url), headers: ua);
        if (dl.statusCode != 200 || dl.bodyBytes.length < 1000) {
          stdout.writeln('İndirilemedi: $name $doc (${dl.statusCode})');
          continue;
        }
        pdf.writeAsBytesSync(dl.bodyBytes);
        final txt = File(pdf.path.replaceAll('.pdf', '.txt'));
        final r = await Process.run('pdftotext', ['-layout', '-enc', 'UTF-8', pdf.path, txt.path]);
        if (r.exitCode != 0 || !txt.existsSync() || txt.lengthSync() < 200) {
          stdout.writeln('Metne çevrilemedi (taranmış PDF olabilir): $name $doc');
          continue;
        }
        manifest.add({
          'product': name,
          'document': doc,
          'file': txt.uri.pathSegments.last,
          'url': url,
          'date': _date('${row[dateKey]}'),
        });
        stdout.writeln('$name $doc ✓');
      }
    }
  }
  File('${out.path}/manifest.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  stdout.writeln('${manifest.length} belge, manifest: ${out.path}/manifest.json');
}

String? _date(String s) {
  final m = RegExp(r'(\d{2})[./](\d{2})[./](\d{4})').firstMatch(s);
  return m == null ? null : '${m[3]}-${m[2]}-${m[1]}';
}
