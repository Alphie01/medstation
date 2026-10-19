import 'package:medstation_core/medstation_core.dart';

final testProvenance = DataProvenance(
  source: 'Test',
  version: 'test',
  fetchedAt: DateTime.utc(2026, 1, 1),
  isSample: true,
);

Drug drug(
  String id,
  List<DrugIngredient> ings, {
  String? form = 'Film tablet',
  RxType rx = RxType.normal,
  bool recalled = false,
  String? barcode,
}) =>
    Drug(
      id: id,
      name: id,
      ingredients: ings,
      provenance: testProvenance,
      form: form,
      rxType: rx,
      recalled: recalled,
      barcode: barcode,
    );

DrugIngredient ing(String name, [double? amount, String? unit = 'mg', double? perMl]) =>
    DrugIngredient(name: name, amount: amount, unit: unit, perVolumeMl: perMl);

PrescriptionLine line(String id, Drug d, {int? times, double? units}) =>
    PrescriptionLine(
      id: id,
      drug: d,
      posology: Posology(timesPerDay: times, unitsPerDose: units),
    );

const src = SourceRef(source: 'Test KÜB');
