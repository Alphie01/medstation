import 'package:medstation_core/medstation_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

T ok<T>(CalcResult<T> r) => (r as CalcOk<T>).value;

void main() {
  group('calculators', () {
    test('weight-based dose with cap and volume', () {
      final r = weightBasedDose(perKg: 15, weightKg: 20, concAmount: 120, concPerMl: 5);
      expect(ok(r).dose, 300);
      expect(ok(r).volumeMl, 12.5);
      final c = weightBasedDose(perKg: 15, weightKg: 80, maxDose: 1000) as CalcOk<WeightDose>;
      expect(c.value.capped, isTrue);
      expect(c.value.dose, 1000);
      expect(c.warnings, isNotEmpty);
    });

    test('invalid input returns errors', () {
      expect(weightBasedDose(perKg: 15, weightKg: null), isA<CalcError>());
      expect(weightBasedDose(perKg: -1, weightKg: 10), isA<CalcError>());
      expect(weightBasedDose(perKg: 10, weightKg: 10, concAmount: 5), isA<CalcError>());
      expect(bsaMosteller(heightCm: 0, weightKg: 70), isA<CalcError>());
      expect(dilution(c1: 10, v1: 1), isA<CalcError>());
      expect(alligation(high: 10, low: 2, target: 12, total: 100), isA<CalcError>());
    });

    test('pediatric range', () {
      expect(ok(pediatricDoseCheck(dailyDose: 900, weightKg: 12, minPerKgDay: 40, maxPerKgDay: 60)),
          DoseRangeStatus.ustunde);
      expect(ok(pediatricDoseCheck(dailyDose: 600, weightKg: 12, minPerKgDay: 40, maxPerKgDay: 60)),
          DoseRangeStatus.aralikta);
    });

    test('bsa, units, mEq, percent, dilution, alligation', () {
      expect(ok(bsaMosteller(heightCm: 180, weightKg: 80)), closeTo(2.0, 0.001));
      expect(ok(convertMass(1.5, MassUnit.g, MassUnit.mg)), 1500);
      expect(ok(convertMass(250, MassUnit.mcg, MassUnit.mg)), 0.25);
      expect(ok(mgToMeq(mg: 1000, molarMass: 74.55, valence: 1)), closeTo(13.41, 0.01)); // KCl
      expect(ok(percentToMgPerMl(0.9)), closeTo(9, 1e-9));
      final d = ok(dilution(c1: 10, v1: null, c2: 2, v2: 100));
      expect(d.v1, 20);
      expect(d.diluent, 80);
      final a = ok(alligation(high: 10, low: 2, target: 5, total: 80));
      expect(a.highAmount, 30);
      expect(a.lowAmount, 50);
    });
  });

  group('search', () {
    final aug = drug('Augmentin', [ing('amoksisilin', 875), ing('klavulanik asit', 125)]);
    final klamoks = drug('Klamoks', [ing('Amoksisilin trihidrat', 875), ing('klavulanik asit', 125)]);
    final largopen = drug('Largopen', [ing('amoksisilin', 1000)], form: 'Tablet');
    final susp = drug('Aug susp', [ing('amoksisilin', 400, 'mg', 5), ing('klavulanik asit', 57, 'mg', 5)],
        form: 'Oral süspansiyon');
    final all = [aug, klamoks, largopen, susp];

    test('incl vs exact', () {
      expect(matchIngredients(all, ['amoksisilin'], MatchMode.incl), hasLength(4));
      expect(matchIngredients(all, ['amoksisilin'], MatchMode.exact), [largopen]);
      expect(matchIngredients(all, ['amoksisilin', 'klavulanik asit'], MatchMode.exact), hasLength(3));
      expect(matchIngredients(all, [], MatchMode.incl), isEmpty);
    });

    test('equivalence groups use ingredient key, amount and form', () {
      final g = groupEquivalents(all);
      expect(g.first.items.map((d) => d.id), ['Augmentin', 'Klamoks']);
      expect(g, hasLength(3));
      expect(equivalentsOf(aug, all), [klamoks]);
    });
  });
}
