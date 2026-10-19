import 'package:medstation_core/medstation_core.dart';
import 'package:test/test.dart';

void main() {
  test('Turkish lower-casing', () {
    expect(trLower('AMOKSİSİLİN'), 'amoksisilin');
    expect(trLower('IBUPROFEN'), 'ıbuprofen');
    expect(searchFold('İBUPROFEN'), 'ibuprofen');
    expect(searchFold('Sefüroksim'), 'sefuroksim');
  });

  test('baseIngredient strips salts but not leading cations', () {
    expect(baseIngredient('Amoksisilin trihidrat'), 'amoksisilin');
    expect(baseIngredient('amoksisilin sodyum'), 'amoksisilin');
    expect(baseIngredient('Metformin HCl'), 'metformin');
    expect(baseIngredient('kalsiyum karbonat'), 'kalsiyum karbonat');
    expect(baseIngredient('sodyum klorür'), 'sodyum');
    expect(baseIngredient('hidroklorür'), 'hidroklorür');
  });
}
