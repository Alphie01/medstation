import 'package:meta/meta.dart';

import '../models/clinical.dart';
import '../models/drug.dart';
import '../models/provenance.dart';
import '../models/text.dart';

/// Verified clinical reference data the rules run against.
///
/// [interactionSource] is null when no interaction database is connected. In
/// that case the engine says so explicitly instead of implying "no
/// interaction".
@immutable
class KnowledgeSnapshot {
  const KnowledgeSnapshot({
    this.interactions = const [],
    this.doseLimits = const [],
    this.recalledBarcodes = const {},
    this.interactionSource,
    this.interactionCoverage = const {},
  });

  final List<Interaction> interactions;
  final List<DoseLimit> doseLimits;
  final Set<String> recalledBarcodes;
  final DataProvenance? interactionSource;

  /// Base ingredient keys the interaction database covers. A pair is only
  /// considered "checked" when both ingredients are covered.
  final Set<String> interactionCoverage;

  bool get interactionDbConnected => interactionSource != null;

  static const empty = KnowledgeSnapshot();
}

abstract class Rule {
  const Rule();
  String get id;
  List<CheckFinding> check(Prescription rx, KnowledgeSnapshot kb);
}

/// Runs every rule and returns findings sorted by priority.
class RuleEngine {
  RuleEngine({List<Rule>? rules}) : rules = rules ?? defaultRules;

  static const defaultRules = <Rule>[
    RecallRule(),
    LicenseRule(),
    PrescriptionTypeRule(),
    InteractionRule(),
    DuplicateIngredientRule(),
    MaxDailyDoseRule(),
    PediatricDataRule(),
    MissingDataRule(),
  ];

  final List<Rule> rules;

  List<CheckFinding> check(Prescription rx, KnowledgeSnapshot kb) {
    final out = <CheckFinding>[];
    for (final r in rules) {
      out.addAll(r.check(rx, kb));
    }
    out.sort((a, b) {
      final s = a.severity.index.compareTo(b.severity.index);
      if (s != 0) return s;
      return a.type.index.compareTo(b.type.index);
    });
    return out;
  }
}

String _lineName(PrescriptionLine l) =>
    [l.drug.name, l.drug.strength].whereType<String>().join(' ');

class RecallRule extends Rule {
  const RecallRule();
  @override
  String get id => 'recall';

  @override
  List<CheckFinding> check(Prescription rx, KnowledgeSnapshot kb) => [
        for (final l in rx.lines)
          if (l.drug.recalled ||
              (l.drug.barcode != null &&
                  kb.recalledBarcodes.contains(l.drug.barcode)))
            CheckFinding(
              ruleId: id,
              type: FindingType.geriCekme,
              severity: Severity.kritik,
              title: '${_lineName(l)} geri çekilen ürünler listesinde',
              detail: 'Ürünü vermeden önce TİTCK geri çekme duyurusunu ve '
                  'seri/lot bilgisini kontrol edin.',
              lineIds: [l.id],
              verified: true,
              source: const SourceRef(source: 'TİTCK geri çekme duyuruları'),
            ),
      ];
}

/// Suspended licenses and products marked passive in SKRS.
class LicenseRule extends Rule {
  const LicenseRule();
  @override
  String get id => 'license';

  @override
  List<CheckFinding> check(Prescription rx, KnowledgeSnapshot kb) => [
        for (final l in rx.lines)
          if (l.drug.licenseStatus.suspended)
            CheckFinding(
              ruleId: id,
              type: FindingType.ruhsat,
              severity: l.drug.licenseStatus == LicenseStatus.farmakovijilansAskida ? Severity.kritik : Severity.onemli,
              title: '${_lineName(l)}: ${l.drug.licenseStatus.label.toLowerCase()}',
              detail: 'TİTCK ruhsatlı ürünler listesinde ruhsatı askıda görünüyor. Vermeden önce güncel durumu kontrol edin.',
              lineIds: [l.id],
              verified: true,
              source: l.drug.provenance.toSourceRef(),
            )
          else if (l.drug.marketStatus == MarketStatus.pasif)
            CheckFinding(
              ruleId: id,
              type: FindingType.ruhsat,
              severity: Severity.bilgi,
              title: '${_lineName(l)}: SKRS listesinde pasif',
              detail: 'Ürün e-Reçete listesinde pasif durumda; eşdeğer bir ürün gerekebilir.',
              lineIds: [l.id],
              verified: true,
              source: l.drug.provenance.toSourceRef(),
            ),
      ];
}

class PrescriptionTypeRule extends Rule {
  const PrescriptionTypeRule();
  @override
  String get id => 'rx-type';

  static const _controlled = {
    RxType.kirmizi,
    RxType.yesil,
    RxType.mor,
    RxType.turuncu,
  };

  @override
  List<CheckFinding> check(Prescription rx, KnowledgeSnapshot kb) {
    final out = <CheckFinding>[];
    for (final l in rx.lines) {
      final need = l.drug.rxType;
      if (!_controlled.contains(need)) continue;
      final given = rx.rxType;
      if (given == null || given == RxType.bilinmiyor) {
        out.add(CheckFinding(
          ruleId: id,
          type: FindingType.receteTuru,
          severity: Severity.onemli,
          title: '${_lineName(l)}: ${need.label} gerektirir',
          detail: 'Reçetenin türü girilmedi. Reçete türünü kontrol edin.',
          lineIds: [l.id],
          verified: true,
          source: l.drug.provenance.toSourceRef(),
        ));
      } else if (given != need) {
        out.add(CheckFinding(
          ruleId: id,
          type: FindingType.receteTuru,
          severity: Severity.kritik,
          title: '${_lineName(l)}: ${need.label} gerekir, reçete '
              '${given.label.toLowerCase()}',
          detail: 'Ürün bu reçete türüyle verilemez.',
          lineIds: [l.id],
          verified: true,
          source: l.drug.provenance.toSourceRef(),
        ));
      }
    }
    return out;
  }
}

class InteractionRule extends Rule {
  const InteractionRule();
  @override
  String get id => 'interaction';

  @override
  List<CheckFinding> check(Prescription rx, KnowledgeSnapshot kb) {
    final lines = rx.lines;
    final pairs = <(PrescriptionLine, String, PrescriptionLine, String)>[];
    for (var i = 0; i < lines.length; i++) {
      for (var j = i + 1; j < lines.length; j++) {
        for (final a in lines[i].drug.ingredients) {
          for (final b in lines[j].drug.ingredients) {
            final ka = baseIngredient(a.name), kb2 = baseIngredient(b.name);
            if (ka == kb2) continue; // handled by DuplicateIngredientRule
            pairs.add((lines[i], ka, lines[j], kb2));
          }
        }
      }
    }
    if (pairs.isEmpty) return const [];

    if (!kb.interactionDbConnected) {
      return [
        CheckFinding(
          ruleId: id,
          type: FindingType.etkilesim,
          severity: Severity.dogrulanamadi,
          title: 'Etkileşim veritabanı bağlı değil',
          detail: '${pairs.length} etken madde çifti kontrol edilemedi. '
              'Bu, etkileşim olmadığı anlamına gelmez; KÜB 4.5 bölümünü '
              'kontrol edin.',
          lineIds: {for (final p in pairs) ...[p.$1.id, p.$3.id]}.toList(),
          verified: false,
        ),
      ];
    }

    final out = <CheckFinding>[];
    final unchecked = <String>{};
    final uncheckedLines = <String>{};
    for (final (la, a, lb, b) in pairs) {
      final hit = kb.interactions.where((x) => x.matches(a, b));
      if (hit.isNotEmpty) {
        for (final x in hit) {
          out.add(CheckFinding(
            ruleId: id,
            type: FindingType.etkilesim,
            severity: x.severity,
            title: '$a + $b',
            detail: [x.summary, if (x.management != null) x.management!]
                .join(' '),
            lineIds: [la.id, lb.id],
            verified: true,
            source: x.source,
          ));
        }
      } else if (!kb.interactionCoverage.contains(a) ||
          !kb.interactionCoverage.contains(b)) {
        unchecked.add('$a + $b');
        uncheckedLines.addAll([la.id, lb.id]);
      }
    }
    if (unchecked.isNotEmpty) {
      out.add(CheckFinding(
        ruleId: id,
        type: FindingType.etkilesim,
        severity: Severity.dogrulanamadi,
        title: 'Bazı çiftler veritabanında yok',
        detail: '${unchecked.join(', ')}: etkileşim verisi bulunamadı, '
            'doğrulanamadı.',
        lineIds: uncheckedLines.toList(),
        verified: false,
        source: kb.interactionSource!.toSourceRef(),
      ));
    }
    return out;
  }
}

class DuplicateIngredientRule extends Rule {
  const DuplicateIngredientRule();
  @override
  String get id => 'duplicate';

  @override
  List<CheckFinding> check(Prescription rx, KnowledgeSnapshot kb) {
    final byIng = <String, List<PrescriptionLine>>{};
    for (final l in rx.lines) {
      for (final k in l.drug.ingredients.map((i) => baseIngredient(i.name))
          .toSet()) {
        byIng.putIfAbsent(k, () => []).add(l);
      }
    }
    return [
      for (final e in byIng.entries)
        if (e.value.length > 1)
          CheckFinding(
            ruleId: id,
            type: FindingType.mukerrer,
            severity: Severity.onemli,
            title: '${e.key} ${e.value.length} kalemde',
            detail: '${e.value.map(_lineName).join(', ')} aynı etken maddeyi '
                'içeriyor. Toplam günlük dozu ve tedavi amacını kontrol edin.',
            lineIds: e.value.map((l) => l.id).toList(),
            verified: true,
            source: e.value.first.drug.provenance.toSourceRef(),
          ),
    ];
  }
}

/// Daily amount of one ingredient for one line, in the ingredient's unit.
/// Returns null if posology or strength is missing.
double? dailyAmount(PrescriptionLine l, DrugIngredient ing) {
  final p = l.posology;
  if (!p.isComplete || ing.amount == null) return null;
  final perUnit = ing.perVolumeMl == null
      ? ing.amount!
      : ing.amount! / ing.perVolumeMl!; // per ml
  return perUnit * p.unitsPerDose! * p.timesPerDay!;
}

class MaxDailyDoseRule extends Rule {
  const MaxDailyDoseRule();
  @override
  String get id => 'max-dose';

  @override
  List<CheckFinding> check(Prescription rx, KnowledgeSnapshot kb) {
    final pop =
        rx.patient.isPediatric ? Population.pediatrik : Population.yetiskin;
    final totals = <String, double>{};
    final units = <String, String>{};
    final contributing = <String, List<String>>{};
    final incomplete = <String>{};
    final unitMismatch = <String>{};

    for (final l in rx.lines) {
      for (final ing in l.drug.ingredients) {
        final k = baseIngredient(ing.name);
        final amt = dailyAmount(l, ing);
        if (amt == null) {
          incomplete.add(k);
          continue;
        }
        final u = units.putIfAbsent(k, () => ing.unit ?? '');
        if (u != (ing.unit ?? '')) {
          unitMismatch.add(k);
          continue;
        }
        totals[k] = (totals[k] ?? 0) + amt;
        contributing.putIfAbsent(k, () => []).add(l.id);
      }
    }

    final out = <CheckFinding>[];
    final noLimit = <String>[];
    for (final e in totals.entries) {
      final limits = kb.doseLimits
          .where((d) => d.ingredient == e.key && d.population == pop)
          .toList();
      if (limits.isEmpty) {
        noLimit.add(e.key);
        continue;
      }
      for (final lim in limits) {
        if (lim.unit != units[e.key]) {
          unitMismatch.add(e.key);
          continue;
        }
        double? ceiling = lim.maxDaily;
        if (lim.maxDailyPerKg != null) {
          final w = rx.patient.weightKg;
          if (w == null) {
            out.add(CheckFinding(
              ruleId: id,
              type: FindingType.dozAsimi,
              severity: Severity.dogrulanamadi,
              title: '${e.key}: kiloya göre doz kontrol edilemedi',
              detail: 'Sınır ${lim.maxDailyPerKg} ${lim.unit}/kg/gün; hasta '
                  'kilosu girilmedi.',
              lineIds: contributing[e.key]!,
              verified: false,
              source: lim.source,
            ));
            continue;
          }
          final perKg = lim.maxDailyPerKg! * w;
          ceiling = ceiling == null ? perKg : (perKg < ceiling ? perKg : ceiling);
        }
        if (ceiling != null && e.value > ceiling) {
          out.add(CheckFinding(
            ruleId: id,
            type: FindingType.dozAsimi,
            severity: Severity.kritik,
            title: '${e.key}: günlük ${_fmt(e.value)} ${lim.unit}',
            detail: 'Üst sınır ${_fmt(ceiling)} ${lim.unit}/gün '
                '(${pop == Population.pediatrik ? 'pediatrik' : 'yetişkin'}). '
                '${incomplete.contains(e.key) ? 'Bazı kalemlerin talimatı eksik; toplam daha yüksek olabilir.' : ''}'
                    .trim(),
            lineIds: contributing[e.key]!,
            verified: true,
            source: lim.source,
          ));
        }
      }
    }
    if (noLimit.isNotEmpty) {
      out.add(CheckFinding(
        ruleId: id,
        type: FindingType.dozAsimi,
        severity: Severity.dogrulanamadi,
        title: 'Maksimum doz verisi yok',
        detail: '${noLimit.join(', ')} için doğrulanmış günlük doz sınırı '
            'tanımlı değil.',
        lineIds: [for (final k in noLimit) ...contributing[k]!],
        verified: false,
      ));
    }
    if (unitMismatch.isNotEmpty) {
      out.add(CheckFinding(
        ruleId: id,
        type: FindingType.dozAsimi,
        severity: Severity.dogrulanamadi,
        title: 'Birimler uyuşmuyor',
        detail: '${unitMismatch.join(', ')} için kalemler farklı birimlerde; '
            'toplam doz hesaplanmadı.',
        lineIds: const [],
        verified: false,
      ));
    }
    return out;
  }
}

class PediatricDataRule extends Rule {
  const PediatricDataRule();
  @override
  String get id => 'pediatric';

  @override
  List<CheckFinding> check(Prescription rx, KnowledgeSnapshot kb) {
    if (!rx.patient.isPediatric || rx.patient.weightKg != null) return const [];
    return [
      CheckFinding(
        ruleId: id,
        type: FindingType.pediatrik,
        severity: Severity.dogrulanamadi,
        title: 'Pediatrik hasta: kilo girilmedi',
        detail: 'Kiloya dayalı doz kontrolleri yapılamaz. Hastanın güncel '
            'kilosunu girin.',
        lineIds: rx.lines.map((l) => l.id).toList(),
        verified: false,
      ),
    ];
  }
}

class MissingDataRule extends Rule {
  const MissingDataRule();
  @override
  String get id => 'missing';

  @override
  List<CheckFinding> check(Prescription rx, KnowledgeSnapshot kb) {
    final out = <CheckFinding>[];
    for (final l in rx.lines) {
      if (l.drug.ingredients.isEmpty) {
        out.add(CheckFinding(
          ruleId: id,
          type: FindingType.eksikVeri,
          severity: Severity.dogrulanamadi,
          title: '${_lineName(l)}: etken madde bilgisi yok',
          detail: l.drug.compositionText == null
              ? 'Bu kalem için hiçbir kontrol yapılamadı.'
              : 'Kaynaktaki bileşim ayrıştırılamadı (“${l.drug.compositionText}”); etkileşim, mükerrer madde ve doz kontrolleri yapılamadı.',
          lineIds: [l.id],
          verified: false,
        ));
        continue;
      }
      if (l.drug.ingredients.any((i) => i.amount == null)) {
        out.add(CheckFinding(
          ruleId: id,
          type: FindingType.eksikVeri,
          severity: Severity.dogrulanamadi,
          title: '${_lineName(l)}: etken madde miktarı yok',
          detail: 'Doz hesabı yapılamadı.',
          lineIds: [l.id],
          verified: false,
        ));
      }
      if (!l.posology.isComplete) {
        out.add(CheckFinding(
          ruleId: id,
          type: FindingType.eksikVeri,
          severity: Severity.bilgi,
          title: '${_lineName(l)}: kullanım talimatı eksik',
          detail: 'Günlük kaç kez ve kaç birim kullanılacağını girin; doz '
              'kontrolü bu kalem için yapılmadı.',
          lineIds: [l.id],
          verified: false,
        ));
      }
    }
    return out;
  }
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

extension on DataProvenance {
  SourceRef toSourceRef() =>
      SourceRef(source: '$source ($version)', url: url, date: fetchedAt);
}
