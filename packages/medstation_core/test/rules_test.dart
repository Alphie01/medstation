import 'package:medstation_core/medstation_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  final engine = RuleEngine();
  final parol = drug('Parol', [ing('parasetamol', 500)]);
  final tylol = drug('Tylol', [ing('Parasetamol', 500)]);
  final ibu = drug('Nurofen', [ing('ibuprofen', 400)]);
  final warfarin = drug('Coumadin', [ing('varfarin sodyum', 5)]);

  group('interactions', () {
    test('no database → explicit unverified finding, never silence', () {
      final f = engine.check(
        Prescription(lines: [line('1', parol, times: 3, units: 1), line('2', ibu, times: 3, units: 1)]),
        KnowledgeSnapshot.empty,
      );
      final i = f.where((x) => x.type == FindingType.etkilesim).single;
      expect(i.severity, Severity.dogrulanamadi);
      expect(i.verified, isFalse);
      expect(i.title, contains('bağlı değil'));
    });

    test('known pair reported with source', () {
      final kb = KnowledgeSnapshot(
        interactionSource: testProvenance,
        interactionCoverage: {'varfarin', 'ibuprofen'},
        interactions: [
          Interaction(a: 'varfarin', b: 'ibuprofen', severity: Severity.kritik,
              summary: 'Kanama riski artar.', source: src),
        ],
      );
      final f = engine.check(
        Prescription(lines: [line('1', warfarin, times: 1, units: 1), line('2', ibu, times: 3, units: 1)]),
        kb,
      );
      final i = f.firstWhere((x) => x.type == FindingType.etkilesim);
      expect(i.severity, Severity.kritik);
      expect(i.source, src);
      expect(f.first, i, reason: 'critical findings sorted first');
    });

    test('pair outside coverage → unverified, covered pair absent → nothing', () {
      final kb = KnowledgeSnapshot(
        interactionSource: testProvenance,
        interactionCoverage: {'parasetamol', 'ibuprofen'},
      );
      var f = engine.check(Prescription(lines: [line('1', parol), line('2', ibu)]), kb);
      expect(f.where((x) => x.type == FindingType.etkilesim), isEmpty);
      f = engine.check(Prescription(lines: [line('1', parol), line('2', warfarin)]), kb);
      expect(f.where((x) => x.type == FindingType.etkilesim).single.verified, isFalse);
    });
  });

  test('duplicate ingredient across brands and salts', () {
    final amox1 = drug('A', [ing('amoksisilin trihidrat', 1000)]);
    final amox2 = drug('B', [ing('Amoksisilin', 875), ing('klavulanik asit', 125)]);
    final f = engine.check(Prescription(lines: [line('1', amox1), line('2', amox2)]), KnowledgeSnapshot.empty);
    final d = f.where((x) => x.type == FindingType.mukerrer).single;
    expect(d.lineIds, ['1', '2']);
    expect(d.title, startsWith('amoksisilin'));
  });

  group('max daily dose', () {
    final limit = DoseLimit(ingredient: 'parasetamol', population: Population.yetiskin,
        unit: 'mg', maxDaily: 4000, source: src);
    final kb = KnowledgeSnapshot(doseLimits: [limit]);

    test('sums across lines and flags overdose', () {
      final f = engine.check(Prescription(lines: [
        line('1', parol, times: 4, units: 1), // 2000
        line('2', tylol, times: 4, units: 2), // 4000
      ]), kb);
      final o = f.firstWhere((x) => x.type == FindingType.dozAsimi);
      expect(o.severity, Severity.kritik);
      expect(o.title, contains('6000'));
    });

    test('within limit → no overdose', () {
      final f = engine.check(Prescription(lines: [line('1', parol, times: 4, units: 2)]), kb);
      expect(f.where((x) => x.severity == Severity.kritik), isEmpty);
    });

    test('liquid per-ml amounts and per-kg pediatric limit', () {
      final syr = drug('Parol şurup', [ing('parasetamol', 120, 'mg', 5)], form: 'Şurup');
      final ped = KnowledgeSnapshot(doseLimits: [
        DoseLimit(ingredient: 'parasetamol', population: Population.pediatrik,
            unit: 'mg', maxDailyPerKg: 60, source: src),
      ]);
      // 10 ml × 4 = 40 ml × 24 mg/ml = 960 mg; 12 kg × 60 = 720 mg.
      var f = engine.check(Prescription(
        lines: [line('1', syr, times: 4, units: 10)],
        patient: const PatientContext(ageYears: 2, weightKg: 12),
      ), ped);
      expect(f.first.type, FindingType.dozAsimi);
      expect(f.first.title, contains('960'));

      f = engine.check(Prescription(
        lines: [line('1', syr, times: 4, units: 10)],
        patient: const PatientContext(ageYears: 2),
      ), ped);
      expect(f.where((x) => x.type == FindingType.pediatrik).single.verified, isFalse);
      expect(f.where((x) => x.type == FindingType.dozAsimi).single.severity,
          Severity.dogrulanamadi);
    });

    test('no limit data → unverified, not silent', () {
      final f = engine.check(Prescription(lines: [line('1', ibu, times: 3, units: 1)]), kb);
      expect(f.where((x) => x.title == 'Maksimum doz verisi yok'), hasLength(1));
    });
  });

  test('missing posology and missing ingredient data', () {
    final unknown = drug('X', []);
    final noAmt = drug('Y', [ing('ibuprofen')]);
    final f = engine.check(Prescription(lines: [line('1', unknown), line('2', noAmt)]), KnowledgeSnapshot.empty);
    expect(f.where((x) => x.type == FindingType.eksikVeri).map((x) => x.title), containsAll([
      'X: etken madde bilgisi yok',
      'Y: etken madde miktarı yok',
      'Y: kullanım talimatı eksik',
    ]));
  });

  test('recall and prescription type', () {
    final r = drug('R', [ing('a', 1)], recalled: true);
    final green = drug('G', [ing('alprazolam', 0.5)], rx: RxType.yesil);
    var f = engine.check(Prescription(lines: [line('1', r)]), KnowledgeSnapshot.empty);
    expect(f.first.type, FindingType.geriCekme);
    f = engine.check(Prescription(lines: [line('1', green)], rxType: RxType.normal), KnowledgeSnapshot.empty);
    expect(f.first.severity, Severity.kritik);
    expect(f.first.type, FindingType.receteTuru);
    f = engine.check(Prescription(lines: [line('1', green)]), KnowledgeSnapshot.empty);
    expect(f.firstWhere((x) => x.type == FindingType.receteTuru).severity, Severity.onemli);
  });

  test('suspended license and passive product', () {
    final fv = Drug(id: 'fv', name: 'FV', ingredients: [ing('a', 1)], provenance: testProvenance,
        licenseStatus: LicenseStatus.farmakovijilansAskida);
    final m23 = Drug(id: 'm', name: 'M', ingredients: [ing('b', 1)], provenance: testProvenance,
        licenseStatus: LicenseStatus.madde23Askida);
    final pasif = Drug(id: 'p', name: 'P', ingredients: [ing('c', 1)], provenance: testProvenance,
        licenseStatus: LicenseStatus.gecerli, marketStatus: MarketStatus.pasif);
    final f = engine.check(Prescription(lines: [line('1', fv), line('2', m23), line('3', pasif)]), KnowledgeSnapshot.empty)
        .where((x) => x.type == FindingType.ruhsat)
        .toList();
    expect(f.map((x) => x.severity), [Severity.kritik, Severity.onemli, Severity.bilgi]);
  });

  test('unparsed source composition is quoted, not guessed', () {
    final d = Drug(id: 'x', name: 'X', ingredients: const [], provenance: testProvenance,
        compositionText: 'parasetamol, combinations excl. psycholeptics');
    final f = engine.check(Prescription(lines: [line('1', d)]), KnowledgeSnapshot.empty);
    expect(f.single.detail, contains('combinations excl. psycholeptics'));
    expect(f.single.verified, isFalse);
  });

  test('json round-trip of prescription and findings', () {
    final rx = Prescription(lines: [line('1', parol, times: 3, units: 1)],
        patient: const PatientContext(ageYears: 40));
    final back = Prescription.fromJson(rx.toJson());
    expect(back.lines.single.drug.ingredients.single.amount, 500);
    final f = engine.check(back, KnowledgeSnapshot.empty);
    expect(f.map((x) => CheckFinding.fromJson(x.toJson()).id), f.map((x) => x.id));
  });
}
