import 'package:medstation_core/medstation_core.dart';
import 'package:medstation_server/medstation_server.dart';
import 'package:medstation_server/src/ingest/chunker.dart';
import 'package:medstation_server/src/ingest/titck_parse.dart';
import 'package:medstation_server/src/ingest/announcements_import.dart';
import 'package:test/test.dart';

void main() {
  test('PII redaction', () {
    final s = redactPii('Hasta: Ayşe Yılmaz, TC 12345678901, tel 0532 123 45 67, a@b.com');
    expect(s, isNot(contains('Ayşe')));
    expect(s, contains('[TCKN]'));
    expect(s, contains('[TELEFON]'));
    expect(s, contains('[E-POSTA]'));
    expect(redactPii('parasetamol 500 mg günde 3'), 'parasetamol 500 mg günde 3');
  });

  test('password hashing', () {
    final h = hashPassword('çok-gizli-parola', iterations: 1000);
    expect(verifyPassword('çok-gizli-parola', h), isTrue);
    expect(verifyPassword('yanlış', h), isFalse);
    expect(verifyPassword('x', 'garbage'), isFalse);
  });

  group('assistant citation validation', () {
    final chunk = Citation(chunkId: 'db-1', drugName: 'X', document: 'KÜB', section: '4.2', excerpt: '...');
    final alias = {'c1': 'db-1'};
    final chunks = {'db-1': chunk};

    test('invented citations are dropped and answer withheld', () {
      final a = AssistantService.validate(
          {'answer': 'Doz 5 g [c9].', 'citations': ['c9'], 'confidence': 'yuksek', 'insufficient': false},
          alias, chunks);
      expect(a.citations, isEmpty);
      expect(a.confidence, Confidence.yok);
      expect(a.answer, isNot(contains('5 g')));
    });

    test('valid citations kept and renumbered', () {
      final a = AssistantService.validate(
          {'answer': 'Günde 3 kez [c1] uygulanır [c7].', 'citations': ['c1', 'c7'], 'confidence': 'yuksek', 'insufficient': false},
          alias, chunks);
      expect(a.citations.single.chunkId, 'db-1');
      expect(a.answer, 'Günde 3 kez [1] uygulanır.');
      expect(a.needsVerification, isFalse);
    });

    test('insufficient → no sources listed', () {
      final a = AssistantService.validate(
          {'answer': 'Pasajlarda yanıt yok [c1].', 'citations': ['c1'], 'confidence': 'dusuk', 'insufficient': true},
          alias, chunks);
      expect(a.citations, isEmpty);
      expect(a.confidence, Confidence.yok);
      expect(a.answer, 'Pasajlarda yanıt yok.');
      expect(a.needsVerification, isTrue);
  });
  });

  test('chunker keeps KÜB section headings', () {
    final c = chunkDocument('KISA ÜRÜN BİLGİSİ\n4.2 Pozoloji ve uygulama şekli\nYetişkinlerde günde 3 kez.\n'
        '4.3 Kontrendikasyonlar\nAşırı duyarlılık.\n');
    expect(c.map((e) => e.section), [null, '4.2 Pozoloji ve uygulama şekli', '4.3 Kontrendikasyonlar']);
    expect(c[1].text, 'Yetişkinlerde günde 3 kez.');
  });

  group('TİTCK parsing', () {
    test('header mapping is accent/case-insensitive', () {
      final m = mapHeaders(['Barkod', 'İLAÇ ADI', 'Etkin Madde', 'ATC Kodu'], {
        'barcode': ['BARKOD'],
        'name': ['ILAC ADI'],
        'ingredients': ['ETKIN MADDE'],
        'atc': ['ATC KODU'],
      });
      expect(m, {'barcode': 0, 'name': 1, 'ingredients': 2, 'atc': 3});
    });

    test('ingredient splitting on real TİTCK cells', () {
      expect(splitIngredients('parasetamol, klorfeniramin maleat ve kodein fosfat'),
          ['parasetamol', 'klorfeniramin maleat', 'kodein fosfat']);
      expect(splitIngredients('salmeterol ksinafoat and flutikazon propiyonat'),
          ['salmeterol ksinafoat', 'flutikazon propiyonat']);
      expect(splitIngredients('amoksisilin trihidrat+potasyum klavulanat'), ['amoksisilin trihidrat', 'potasyum klavulanat']);
      expect(splitIngredients('insülin (rekombinant, insan)'), ['insülin (rekombinant, insan)']);
      expect(splitIngredients('parasetamol/fenilefrin HCl/dekstrometorfan HBr'), ['parasetamol', 'fenilefrin HCl', 'dekstrometorfan HBr']);
      // ATC phrases and vaccine strain text are kept raw, never split.
      expect(splitIngredients('parasetamol, combinations excl. psycholeptics'), isNull);
      expect(splitIngredients('parasetamol klorfeniramin maleat fenilefrin hcl'), isNull);
      expect(splitIngredients('metformin hidroklorür'), ['metformin hidroklorür']);
      expect(splitIngredients('kodein fosfat hemihidrat'), ['kodein fosfat hemihidrat']);
      expect(splitIngredients('İnfluenza Virüsü Suşları;A/Victoria/4897/2022 (H1N1)'), isNull);
    });

    test('amounts only for single-ingredient products', () {
      var r = ingredientsFrom('dekzametazon', 'ONADRON 0.75 MG TABLET, 100 TABLET');
      expect(r.ingredients.single.amount, 0.75);
      r = ingredientsFrom('parasetamol', 'PAROL 120 MG/5 ML ŞURUP, 150 ML');
      expect(r.ingredients.single.amount, 120);
      expect(r.ingredients.single.perVolumeMl, 5);
      // Combination: amount order in the name is not reliable → no amounts.
      r = ingredientsFrom('parasetamol, klorfeniramin maleat', 'A-FERİN 1 MG +160 MG/5 ML PEDİYATRİK ŞURUP, 100 ML');
      expect(r.ingredients.map((i) => i.amount), [null, null]);
      expect(r.raw, 'parasetamol, klorfeniramin maleat');
      r = ingredientsFrom('parasetamol, combinations excl. psycholeptics', 'AFEBRYL C 300 MG/300 MG/200 MG');
      expect(r.ingredients, isEmpty);
      expect(r.raw, contains('combinations'));
    });

    test('strength label, pack and header prefix aliases', () {
      expect(strengthFromName('AFEBRYL C 300 MG/300 MG/200 MG EFERVESAN TABLET (16 ADET)')!.label, '300 MG/300 MG/200 MG');
      expect(strengthFromName('A-FERİN 1 MG +160 MG/5 ML PEDİYATRİK ŞURUP')!.label, '1 MG +160 MG/5 ML');
      expect(packFromName('EPICLO 25 MG FILM KAPLI TABLET (30 ADET)'), '30 ADET');
      expect(packFromName('ONADRON 0.75 MG TABLET, 100 TABLET'), '100 TABLET');
      final m = mapHeaders(['BARKOD', 'RUHSATI ASKIDA OLMAYAN ÜRÜN: 0\nMADDE-23 ...'], {
        'barcode': ['BARKOD'],
        'license': ['RUHSATI ASKIDA*'],
      });
      expect(m, {'barcode': 0, 'license': 1});
    });

    test('price and rx type', () {
      expect(priceFrom('1.234,56 TL'), 1234.56);
      expect(priceFrom(12.5), 12.5);
      expect(priceFrom('-'), isNull);
      expect(rxFrom('Yeşil Reçete'), RxType.yesil);
      expect(rxFrom('?'), RxType.bilinmiyor);
      expect(formFromName('X 500 MG FILM KAPLI TABLET'), 'film kapli tablet');
    });
  });

  test('latest TİTCK publication from module page rows', () {
    const page = '''
<table><tbody>
<tr><td><div class="cell">Ruhsatlı Beşeri Tıbbi Ürünler Listesi</div></td>
<td><div class="cell"><i></i>09/10/2026</div></td>
<td><a href="https://titck.gov.tr/storage/a09.xlsx" class="badge">XLSX</a></td></tr>
<tr><td><div class="cell">Ruhsatlı Beşeri Tıbbi Ürünler Listesi</div></td>
<td><div class="cell"><i></i>16/10/2026</div></td>
<td><a href="https://titck.gov.tr/storage/a16.xlsx" class="badge">XLSX</a></td></tr>
<tr><td>PDF only</td><td>20/10/2026</td><td><a href="/x.pdf">PDF</a></td></tr>
</tbody></table>''';
    final p = parseLatestPublication(page, 'https://www.titck.gov.tr/dinamikmodul/85');
    expect(p.version, '2026-10-16');
    expect(p.url, 'https://titck.gov.tr/storage/a16.xlsx');
    expect(() => parseLatestPublication('<p>yok</p>', 'x'), throwsStateError);
    expect(classifyAnnouncement('İlaç Geri Çekme', const []), 'geriCekme');
    expect(classifyAnnouncement('Kamuoyunun Dikkatine', const ['Fiyat Duyurusu']), 'fiyat');
  });
}
