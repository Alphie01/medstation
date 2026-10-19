import 'package:medstation_core/medstation_core.dart';
import 'package:test/test.dart';

void main() {
  const gs = '\u001d';

  test('karekod with FNC1 separators', () {
    final d = Gs1Parser.parse('0108699522095018' '21ABC123$gs' '17281130' '10LOT9');
    expect(d.gtin, '08699522095018');
    expect(d.barcode, '8699522095018');
    expect(d.serial, 'ABC123');
    expect(d.expiry, DateTime(2028, 11, 30));
    expect(d.lot, 'LOT9');
    expect(d.ambiguous, isFalse);
  });

  test('symbology prefix and parenthesised form', () {
    expect(Gs1Parser.parse(']d20108699522095018').gtin, '08699522095018');
    final d = Gs1Parser.parse('(01)08699522095018(17)270600(10)A1(21)S1');
    expect(d.expiry, DateTime(2027, 6, 30)); // DD=00 → last day
    expect(d.lot, 'A1');
  });

  test('missing separator is inferred and flagged ambiguous', () {
    final d = Gs1Parser.parse('0108699522095018' '21SERIAL1' '17281130' '10LOT9');
    expect(d.serial, 'SERIAL1');
    expect(d.lot, 'LOT9');
    expect(d.ambiguous, isTrue);
  });

  test('plain EAN-13', () {
    expect(Gs1Parser.parse('8699522095018').gtin, '08699522095018');
  });

  test('rejects bad check digit and dates', () {
    expect(() => Gs1Parser.parse('0108699522095019'),
        throwsA(isA<Gs1FormatException>()));
    expect(() => Gs1Parser.parse('0108699522095018' '17281340'),
        throwsA(isA<Gs1FormatException>()));
  });
}
