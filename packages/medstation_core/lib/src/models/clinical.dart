import 'package:meta/meta.dart';

import 'drug.dart';
import 'provenance.dart';
import 'text.dart';

/// Finding priority. Order matters: lower index = shown first.
enum Severity {
  kritik('Kritik'),
  onemli('Önemli'),
  dogrulanamadi('Doğrulanamadı'),
  bilgi('Bilgi');

  const Severity(this.label);
  final String label;

  static Severity parse(String? v) =>
      Severity.values.firstWhere((e) => e.name == v, orElse: () => bilgi);
}

/// A verified drug–drug interaction record. Only records with a [source]
/// are loaded into the knowledge snapshot.
@immutable
class Interaction {
  const Interaction({
    required this.a,
    required this.b,
    required this.severity,
    required this.summary,
    required this.source,
    this.management,
  });

  /// Ingredient keys (see [ingredientKey]).
  final String a;
  final String b;
  final Severity severity;
  final String summary;
  final String? management;
  final SourceRef source;

  bool matches(String x, String y) =>
      (a == x && b == y) || (a == y && b == x);

  factory Interaction.fromJson(Map<String, dynamic> j) => Interaction(
        a: ingredientKey(j['a'] as String),
        b: ingredientKey(j['b'] as String),
        severity: Severity.parse(j['severity'] as String?),
        summary: j['summary'] as String,
        management: j['management'] as String?,
        source: SourceRef.fromJson(j['source'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'a': a,
        'b': b,
        'severity': severity.name,
        'summary': summary,
        'management': management,
        'source': source.toJson(),
      };
}

enum Population { yetiskin, pediatrik }

/// Maximum daily dose for an ingredient in a population, from a cited source.
@immutable
class DoseLimit {
  const DoseLimit({
    required this.ingredient,
    required this.population,
    required this.unit,
    required this.source,
    this.maxDaily,
    this.maxDailyPerKg,
  }) : assert(maxDaily != null || maxDailyPerKg != null);

  final String ingredient;
  final Population population;
  final String unit;

  /// Absolute ceiling per day (e.g. 4000 mg).
  final double? maxDaily;

  /// Weight-based ceiling per day (e.g. 60 mg/kg/gün). Requires weight.
  final double? maxDailyPerKg;
  final SourceRef source;

  factory DoseLimit.fromJson(Map<String, dynamic> j) => DoseLimit(
        ingredient: ingredientKey(j['ingredient'] as String),
        population: Population.values.byName(j['population'] as String),
        unit: j['unit'] as String,
        maxDaily: (j['maxDaily'] as num?)?.toDouble(),
        maxDailyPerKg: (j['maxDailyPerKg'] as num?)?.toDouble(),
        source: SourceRef.fromJson(j['source'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'ingredient': ingredient,
        'population': population.name,
        'unit': unit,
        'maxDaily': maxDaily,
        'maxDailyPerKg': maxDailyPerKg,
        'source': source.toJson(),
      };
}

/// Posology as entered or confirmed by the pharmacist. Null fields mean
/// "not stated" — rules then report missing data instead of assuming.
@immutable
class Posology {
  const Posology({this.timesPerDay, this.unitsPerDose, this.days});

  final int? timesPerDay;

  /// Tablets/capsules per intake, or millilitres for liquid forms.
  final double? unitsPerDose;
  final int? days;

  bool get isComplete => timesPerDay != null && unitsPerDose != null;

  factory Posology.fromJson(Map<String, dynamic> j) => Posology(
        timesPerDay: j['timesPerDay'] as int?,
        unitsPerDose: (j['unitsPerDose'] as num?)?.toDouble(),
        days: j['days'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'timesPerDay': timesPerDay,
        'unitsPerDose': unitsPerDose,
        'days': days,
      };
}

@immutable
class PrescriptionLine {
  const PrescriptionLine({
    required this.id,
    required this.drug,
    this.posology = const Posology(),
    this.boxes = 1,
  });

  final String id;
  final Drug drug;
  final Posology posology;
  final int boxes;

  factory PrescriptionLine.fromJson(Map<String, dynamic> j) =>
      PrescriptionLine(
        id: j['id'] as String,
        drug: Drug.fromJson(j['drug'] as Map<String, dynamic>),
        posology: j['posology'] == null
            ? const Posology()
            : Posology.fromJson(j['posology'] as Map<String, dynamic>),
        boxes: j['boxes'] as int? ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'drug': drug.toJson(),
        'posology': posology.toJson(),
        'boxes': boxes,
      };
}

/// Anonymous patient context. No identity is stored or transmitted.
@immutable
class PatientContext {
  const PatientContext({this.ageYears, this.weightKg});

  final double? ageYears;
  final double? weightKg;

  bool get isPediatric => ageYears != null && ageYears! < 18;

  factory PatientContext.fromJson(Map<String, dynamic> j) => PatientContext(
        ageYears: (j['ageYears'] as num?)?.toDouble(),
        weightKg: (j['weightKg'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {'ageYears': ageYears, 'weightKg': weightKg};
}

@immutable
class Prescription {
  const Prescription({
    required this.lines,
    this.patient = const PatientContext(),
    this.rxType,
  });

  final List<PrescriptionLine> lines;
  final PatientContext patient;

  /// Colour of the physical/e-prescription, when known.
  final RxType? rxType;

  factory Prescription.fromJson(Map<String, dynamic> j) => Prescription(
        lines: (j['lines'] as List)
            .map((e) => PrescriptionLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        patient: j['patient'] == null
            ? const PatientContext()
            : PatientContext.fromJson(j['patient'] as Map<String, dynamic>),
        rxType: j['rxType'] == null ? null : RxType.parse(j['rxType'] as String),
      );

  Map<String, dynamic> toJson() => {
        'lines': lines.map((e) => e.toJson()).toList(),
        'patient': patient.toJson(),
        'rxType': rxType?.name,
      };
}

enum FindingType {
  etkilesim('Etkileşim'),
  mukerrer('Mükerrer etken madde'),
  dozAsimi('Doz aşımı'),
  pediatrik('Pediatrik doz'),
  eksikVeri('Eksik veri'),
  geriCekme('Geri çekilen ürün'),
  ruhsat('Ruhsat durumu'),
  receteTuru('Reçete türü');

  const FindingType(this.label);
  final String label;
}

/// One item on the prescription checklist.
@immutable
class CheckFinding {
  const CheckFinding({
    required this.ruleId,
    required this.type,
    required this.severity,
    required this.title,
    required this.detail,
    required this.lineIds,
    required this.verified,
    this.source,
  });

  final String ruleId;
  final FindingType type;
  final Severity severity;
  final String title;
  final String detail;
  final List<String> lineIds;

  /// False when the finding exists because data is missing or unverifiable.
  final bool verified;
  final SourceRef? source;

  /// Stable id so a pharmacist's decision can be attached to it.
  String get id => '$ruleId:${(lineIds.toList()..sort()).join(',')}:$title';

  factory CheckFinding.fromJson(Map<String, dynamic> j) => CheckFinding(
        ruleId: j['ruleId'] as String,
        type: FindingType.values.byName(j['type'] as String),
        severity: Severity.parse(j['severity'] as String?),
        title: j['title'] as String,
        detail: j['detail'] as String,
        lineIds: (j['lineIds'] as List).cast<String>(),
        verified: j['verified'] as bool,
        source: j['source'] == null
            ? null
            : SourceRef.fromJson(j['source'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'ruleId': ruleId,
        'type': type.name,
        'severity': severity.name,
        'title': title,
        'detail': detail,
        'lineIds': lineIds,
        'verified': verified,
        'source': source?.toJson(),
      };
}
