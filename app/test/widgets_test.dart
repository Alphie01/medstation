import 'package:medstation/core/network/api_client.dart';
import 'package:medstation/core/storage/session_store.dart';
import 'package:medstation/core/widgets/common.dart';
import 'package:medstation/features/prescription/check_result_screen.dart';
import 'package:medstation/features/prescription/prescription_draft.dart';
import 'package:medstation/features/search/results_screen.dart';
import 'package:medstation/features/search/search_repository.dart';
import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final prov = DataProvenance(source: 'Test listesi', version: '2026-10', fetchedAt: DateTime(2026, 10, 1), isSample: true);

Drug d(String id, List<DrugIngredient> ings, {String form = 'Film tablet'}) =>
    Drug(id: id, name: id, ingredients: ings, provenance: prov, form: form, firm: 'Firma');

DrugIngredient i(String n, double a) => DrugIngredient(name: n, amount: a, unit: 'mg');

class FakeSearch extends SearchRepository {
  FakeSearch() : super(ApiClient(baseUrl: 'http://x', store: SessionStore()));
  final queries = <SearchQuery>[];

  @override
  Future<SearchResponse> search(SearchQuery q) async {
    queries.add(q);
    final all = [
      d('Augmentin', [i('amoksisilin', 875), i('klavulanik asit', 125)]),
      d('Klamoks', [i('amoksisilin', 875), i('klavulanik asit', 125)]),
      d('Largopen', [i('amoksisilin', 1000)], form: 'Tablet'),
    ];
    final items = matchIngredients(all, q.ingredients, q.mode);
    return SearchResponse(items, 3, 1, const {'tablet': 3});
  }
}

Widget app(Widget child, {List overrides = const []}) => ProviderScope(
      overrides: [...overrides],
      child: MaterialApp(home: child),
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('risk badges always pair colour with label and icon', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [for (final s in Severity.values) RiskBadge(s)]))));
    for (final s in Severity.values) {
      expect(find.text(s.label), findsOneWidget);
    }
    expect(find.byType(Icon), findsNWidgets(Severity.values.length));
  });

  testWidgets('results: incl/exact counts, equivalence groups, sample banner', (t) async {
    final fake = FakeSearch();
    await t.pumpWidget(app(const ResultsScreen(ingredients: ['amoksisilin']),
        overrides: [searchRepositoryProvider.overrideWithValue(fake)]));
    await t.pumpAndSettle();
    expect(find.text('3'), findsWidgets);
    expect(find.text('içeren ilaç'), findsOneWidget);
    expect(find.textContaining('2 ürün'), findsOneWidget, reason: 'Augmentin + Klamoks grouped');
    expect(find.byType(SampleBanner), findsOneWidget);
    expect(find.textContaining('Ayrıca klavulanik asit içerir', findRichText: true), findsOneWidget, reason: '"Ayrıca … içerir" for the extra ingredient');

    await t.tap(find.text('tam eşdeğer'));
    await t.pumpAndSettle();
    expect(fake.queries.last.mode, MatchMode.exact);
    expect(find.text('Largopen'), findsOneWidget);
    expect(find.text('Augmentin'), findsNothing);
  });

  testWidgets('check result: sorted findings, unverified marker, commercial section separate', (t) async {
    final parol = d('Parol', [i('parasetamol', 500)]);
    final rx = Prescription(lines: [
      PrescriptionLine(id: 'a', drug: parol, posology: const Posology(timesPerDay: 4, unitsPerDose: 2)),
      PrescriptionLine(id: 'b', drug: d('Tylol', [i('parasetamol', 500)]), posology: const Posology(timesPerDay: 4, unitsPerDose: 2)),
      PrescriptionLine(id: 'c', drug: d('Nurofen', [i('ibuprofen', 400)])),
    ]);
    final kb = KnowledgeSnapshot(doseLimits: [
      DoseLimit(ingredient: 'parasetamol', population: Population.yetiskin, unit: 'mg', maxDaily: 4000, source: const SourceRef(source: 'Test KÜB')),
    ]);
    final findings = RuleEngine().check(rx, kb);
    final result = CheckResult({
      'checkId': 'x',
      'checkedAt': DateTime(2026, 10, 19).toIso8601String(),
      'lines': rx.lines.map((l) => l.toJson()).toList(),
      'findings': findings.map((f) => f.toJson()).toList(),
      'knowledge': {'interactionDb': null},
      'clinicalAlternatives': [],
      'commercialSuggestions': {'connected': false, 'items': []},
    });

    final container = ProviderContainer();
    container.read(lastCheckProvider.notifier).set(result);
    await t.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: CheckResultScreen())));
    await t.pumpAndSettle();

    expect(find.textContaining('parasetamol: günlük 8000'), findsOneWidget);
    expect(find.text('Etkileşim veritabanı bağlı değil'), findsOneWidget);
    expect(find.text('doğrulanmadı'), findsWidgets);
    final crit = t.getTopLeft(find.textContaining('parasetamol: günlük 8000')).dy;
    final unknown = t.getTopLeft(find.text('Etkileşim veritabanı bağlı değil')).dy;
    expect(crit, lessThan(unknown), reason: 'critical first');

    await t.scrollUntilVisible(find.text('TİCARİ · KLİNİK ÖNERİ DEĞİLDİR'), 300);
    expect(find.text('Klinik alternatifler'), findsOneWidget);
    expect(find.textContaining('destekleyici ürün kataloğu boş'), findsOneWidget);
  });
}
