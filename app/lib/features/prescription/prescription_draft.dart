import 'package:medstation_core/medstation_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';

class DraftLine {
  DraftLine({required this.id, required this.drug, this.posology = const Posology()});
  final String id;
  final Drug drug;
  final Posology posology;

  DraftLine copyWith({Posology? posology}) => DraftLine(id: id, drug: drug, posology: posology ?? this.posology);
}

class PrescriptionDraft {
  const PrescriptionDraft({this.lines = const [], this.ageYears, this.weightKg, this.rxType});
  final List<DraftLine> lines;
  final double? ageYears;
  final double? weightKg;
  final RxType? rxType;

  PrescriptionDraft copyWith({
    List<DraftLine>? lines,
    double? Function()? ageYears,
    double? Function()? weightKg,
    RxType? Function()? rxType,
  }) =>
      PrescriptionDraft(
        lines: lines ?? this.lines,
        ageYears: ageYears == null ? this.ageYears : ageYears(),
        weightKg: weightKg == null ? this.weightKg : weightKg(),
        rxType: rxType == null ? this.rxType : rxType(),
      );

  Map<String, dynamic> toRequest() => {
        'lines': [
          for (final l in lines) {'id': l.id, 'drugId': l.drug.id, 'posology': l.posology.toJson()},
        ],
        'patient': {'ageYears': ageYears, 'weightKg': weightKg},
        'rxType': rxType?.name,
      };
}

/// The prescription being checked. Kept in memory only: no patient identity
/// is ever entered, and the draft is cleared after use.
class PrescriptionDraftNotifier extends Notifier<PrescriptionDraft> {
  var _seq = 0;

  @override
  PrescriptionDraft build() => const PrescriptionDraft();

  void addDrug(Drug d) => state = state.copyWith(lines: [...state.lines, DraftLine(id: 'l${++_seq}', drug: d)]);
  void remove(String id) => state = state.copyWith(lines: state.lines.where((l) => l.id != id).toList());
  void setPosology(String id, Posology p) =>
      state = state.copyWith(lines: [for (final l in state.lines) l.id == id ? l.copyWith(posology: p) : l]);
  void setAge(double? v) => state = state.copyWith(ageYears: () => v);
  void setWeight(double? v) => state = state.copyWith(weightKg: () => v);
  void setRxType(RxType? v) => state = state.copyWith(rxType: () => v);
  void clear() => state = const PrescriptionDraft();
}

final prescriptionDraftProvider =
    NotifierProvider<PrescriptionDraftNotifier, PrescriptionDraft>(PrescriptionDraftNotifier.new);

class CheckResult {
  CheckResult(this.raw)
      : checkId = raw['checkId'] as String,
        checkedAt = DateTime.parse(raw['checkedAt'] as String),
        lines = (raw['lines'] as List).map((e) => PrescriptionLine.fromJson(e as Map<String, dynamic>)).toList(),
        findings = (raw['findings'] as List).map((e) => CheckFinding.fromJson(e as Map<String, dynamic>)).toList(),
        interactionDb = (raw['knowledge'] as Map)['interactionDb'] == null
            ? null
            : DataProvenance.fromJson((raw['knowledge'] as Map)['interactionDb'] as Map<String, dynamic>),
        alternatives = {
          for (final a in raw['clinicalAlternatives'] as List)
            a['lineId'] as String: (a['items'] as List).map((e) => Drug.fromJson(e as Map<String, dynamic>)).toList(),
        },
        commercialConnected = (raw['commercialSuggestions'] as Map)['connected'] as bool,
        commercialItems = ((raw['commercialSuggestions'] as Map)['items'] as List).cast<Map<String, dynamic>>();

  final Map<String, dynamic> raw;
  final String checkId;
  final DateTime checkedAt;
  final List<PrescriptionLine> lines;
  final List<CheckFinding> findings;
  final DataProvenance? interactionDb;
  final Map<String, List<Drug>> alternatives;
  final bool commercialConnected;

  /// The pharmacy's own catalog entries triggered by this prescription.
  final List<Map<String, dynamic>> commercialItems;

  bool get anySample => lines.any((l) => l.drug.provenance.isSample);
  int count(Severity s) => findings.where((f) => f.severity == s).length;
  String lineName(String id) {
    final l = lines.where((l) => l.id == id).firstOrNull;
    return l == null ? id : [l.drug.name, l.drug.strength].whereType<String>().join(' ');
  }
}

class PrescriptionRepository {
  PrescriptionRepository(this.api);
  final ApiClient api;

  Future<CheckResult> check(PrescriptionDraft d) async => CheckResult(await api.post('/prescriptions/check', d.toRequest()));

  Future<void> decide(String checkId, String findingId, String decision, {String? note}) =>
      api.post('/prescriptions/$checkId/decisions', {'findingId': findingId, 'decision': decision, 'note': note});

  /// Throws ApiException(integration_not_authorized) until an official
  /// MEDULA integration is configured on the server.
  Future<List<PrescriptionLine>> fromMedula(String code) async {
    final r = await api.get('/prescriptions/medula/${Uri.encodeComponent(code)}');
    return (r['lines'] as List).map((e) => PrescriptionLine.fromJson(e as Map<String, dynamic>)).toList();
  }
}

final prescriptionRepositoryProvider = Provider((ref) => PrescriptionRepository(ref.watch(apiProvider)));

/// Most recent check result, shown on the result screen.
class LastCheck extends Notifier<CheckResult?> {
  @override
  CheckResult? build() => null;
  void set(CheckResult? r) => state = r;
}

final lastCheckProvider = NotifierProvider<LastCheck, CheckResult?>(LastCheck.new);
