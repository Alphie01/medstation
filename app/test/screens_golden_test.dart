@Tags(['golden'])
library;

import 'dart:io';

import 'package:medstation/core/network/api_client.dart';
import 'package:medstation/core/providers.dart';
import 'package:medstation/core/storage/session_store.dart';
import 'package:medstation/core/theme/theme.dart';
import 'package:medstation/features/auth/login_screen.dart';
import 'package:medstation/features/prescription/check_result_screen.dart';
import 'package:medstation/features/prescription/prescription_draft.dart';
import 'package:medstation/features/prescription/prescription_screen.dart';
import 'package:medstation/features/search/detail_screen.dart';
import 'package:medstation/features/search/home_screen.dart';
import 'package:medstation/features/search/results_screen.dart';
import 'package:medstation/features/search/search_repository.dart';
import 'package:medstation/features/stock/stock_repository.dart';
import 'package:medstation/features/stock/stock_screen.dart';
import 'package:medstation/features/tools/tools_screen.dart';
import 'package:medstation/features/assistant/assistant_screen.dart';
import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders key screens at the reference artboard size (390×844) with the
/// real fonts, for visual comparison with the design canvas.
/// Run: flutter test --tags golden --update-goldens test/screens_golden_test.dart
final prov = DataProvenance(source: 'ÖRNEK VERİ', version: 'dev', fetchedAt: DateTime(2026, 10, 19), isSample: true);

DrugIngredient i(String n, double a, [double? ml]) => DrugIngredient(name: n, amount: a, unit: 'mg', perVolumeMl: ml);

final drugs = [
  Drug(id: 'a1', name: 'Augmentin BID', strength: '1000 mg', form: 'Film kaplı tablet', firm: 'GSK', pack: '14 film tablet', barcode: '8699522095018', atc: 'J01CR02', rxType: RxType.normal, psf: 214.5, ingredients: [i('amoksisilin', 875), i('klavulanik asit', 125)], provenance: prov),
  Drug(id: 'a2', name: 'Klamoks BID', strength: '1000 mg', form: 'Film kaplı tablet', firm: 'Bilim', pack: '14 film tablet', ingredients: [i('amoksisilin', 875), i('klavulanik asit', 125)], provenance: prov),
  Drug(id: 'a3', name: 'Amoklavin BID', strength: '1000 mg', form: 'Film kaplı tablet', firm: 'Deva', pack: '14 film tablet', ingredients: [i('amoksisilin', 875), i('klavulanik asit', 125)], provenance: prov),
  Drug(id: 'a4', name: 'Augmentin BID', strength: '400/57 mg/5 ml', form: 'Oral süspansiyon', firm: 'GSK', ingredients: [i('amoksisilin', 400, 5), i('klavulanik asit', 57, 5)], provenance: prov),
  Drug(id: 'a5', name: 'Largopen', strength: '1 g', form: 'Tablet', firm: 'Bilim', ingredients: [i('amoksisilin', 1000)], provenance: prov),
];

class FakeSearch extends SearchRepository {
  FakeSearch() : super(ApiClient(baseUrl: 'http://x', store: SessionStore()));
  @override
  Future<SearchResponse> search(SearchQuery q) async {
    var items = matchIngredients(drugs, q.ingredients, q.mode);
    final forms = <String, int>{};
    for (final d in items) {
      forms[d.formGroup.name] = (forms[d.formGroup.name] ?? 0) + 1;
    }
    if (q.form != null) items = items.where((d) => d.formGroup == q.form).toList();
    return SearchResponse(items, matchIngredients(drugs, q.ingredients, MatchMode.incl).length,
        matchIngredients(drugs, q.ingredients, MatchMode.exact).length, forms);
  }

  @override
  Future<List<IngredientHit>> top() async => [
        IngredientHit('amoksisilin', 42), IngredientHit('parasetamol', 61), IngredientHit('ibuprofen', 38), IngredientHit('metformin', 27),
      ];
  @override
  Future<Drug> drug(String id) async => drugs.firstWhere((d) => d.id == id);
  @override
  Future<List<Drug>> equivalents(String id) async => equivalentsOf(drugs.firstWhere((d) => d.id == id), drugs);
  @override
  Future<List<Drug>> favorites() async => const [];
}

class FakeSessionStore extends SessionStore {
  @override
  Future<StoredSession?> read() async => null;
}

class FakeStock extends StockRepository {
  FakeStock() : super(ApiClient(baseUrl: 'http://x', store: SessionStore()));
  @override
  Future<List<StockMovement>> movements({int limit = 100}) async => [
        StockMovement({'direction': 'cikis', 'quantity': 1, 'serial': 'S1', 'at': '2026-10-19T12:00:00Z', 'drugId': 'a1', 'drugName': 'Augmentin BID 1000 mg', 'userName': 'Teknisyen'}),
      ];
  @override
  Future<StockAlerts> alerts({int days = 90}) async {
    final item = StockItem(id: 's1', drugId: 'a1', drugName: 'Augmentin BID 1000 mg', criticalLevel: 5, batches: [
      StockBatch(id: 'b1', lot: 'L2391', expiry: DateTime.now().add(const Duration(days: 18)), quantity: 4),
    ]);
    return StockAlerts({
      'expiring': [
        {'item': item.toJson(), 'batch': item.batches.first.toJson(), 'daysLeft': 18},
      ],
      'critical': [item.toJson()],
      'outOfStock': [
        {
          'item': StockItem(id: 's2', drugId: 'a5', drugName: 'Largopen 1 g', batches: const []).toJson(),
          'alternatives': [],
        }
      ],
    });
  }
}

final meta = Meta({
  'sources': [
    {'kind': 'drugs', 'source': 'ÖRNEK VERİ', 'version': 'dev', 'fetchedAt': '2026-10-19T10:00:00Z', 'isSample': true},
  ],
  'interactionDbConnected': false,
  'medulaAvailable': false,
  'assistantAvailable': true,
});

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    await loader.load();
  }

  await load(display, 'assets/fonts/BricolageGrotesque.ttf');
  await load(body, 'assets/fonts/InstrumentSans.ttf');
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/development/flutter';
  await load('MaterialIcons', '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
}

void main() {
  late SharedPreferences prefs;
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await _loadFonts();
    SharedPreferences.setMockInitialValues({
      'recent_searches': '[{"i":["amoksisilin","klavulanik asit"],"t":"2026-10-19T14:32:00"},{"i":["parasetamol"],"t":"2026-10-19T11:05:00"},{"i":["metformin"],"t":"2026-10-18T09:00:00"}]',
    });
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> shot(WidgetTester t, String name, Widget screen, {void Function(ProviderContainer)? setup}) async {
    t.view.physicalSize = const Size(780, 1688);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final c = ProviderContainer(overrides: [
      prefsProvider.overrideWithValue(prefs),
      sessionStoreProvider.overrideWithValue(FakeSessionStore()),
      searchRepositoryProvider.overrideWithValue(FakeSearch()),
      stockRepositoryProvider.overrideWithValue(FakeStock()),
      metaProvider.overrideWith((ref) async => meta),
    ]);
    addTearDown(c.dispose);
    setup?.call(c);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: screen),
    ));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('home', (t) => shot(t, '1_home', const HomeScreen()));
  testWidgets('home with chips', (t) => shot(t, '2_home_chips', const HomeScreen(),
      setup: (c) => c.read(searchDraftProvider.notifier).set(['amoksisilin', 'klavulanik asit'])));
  testWidgets('results', (t) => shot(t, '3_results', const ResultsScreen(ingredients: ['amoksisilin'])));
  testWidgets('detail', (t) => shot(t, '4_detail', const DetailScreen(id: 'a1')));
  testWidgets('prescription', (t) => shot(t, '5_prescription', const PrescriptionScreen(), setup: (c) {
        final n = c.read(prescriptionDraftProvider.notifier);
        n.addDrug(drugs[0]);
        n.addDrug(drugs[4]);
      }));
  testWidgets('check result', (t) {
    final rx = Prescription(lines: [
      PrescriptionLine(id: 'l1', drug: drugs[0], posology: const Posology(timesPerDay: 2, unitsPerDose: 1)),
      PrescriptionLine(id: 'l2', drug: drugs[4]),
    ]);
    final f = RuleEngine().check(rx, KnowledgeSnapshot.empty);
    final r = CheckResult({
      'checkId': 'x',
      'checkedAt': DateTime(2026, 10, 19, 15, 20).toIso8601String(),
      'lines': rx.lines.map((l) => l.toJson()).toList(),
      'findings': f.map((e) => e.toJson()).toList(),
      'knowledge': {'interactionDb': null},
      'clinicalAlternatives': [
        {'lineId': 'l1', 'items': [drugs[1].toJson(), drugs[2].toJson()]},
      ],
      'commercialSuggestions': {'connected': false, 'items': []},
    });
    return shot(t, '6_check', const CheckResultScreen(), setup: (c) => c.read(lastCheckProvider.notifier).set(r));
  });
  testWidgets('stock', (t) => shot(t, '7_stock', const StockScreen()));
  testWidgets('login', (t) => shot(t, '8_login', const LoginScreen()));
  testWidgets('tools', (t) => shot(t, '9_tools', const ToolScreen(id: 'doz')));
  testWidgets('assistant', (t) => shot(t, '10_assistant', const AssistantScreen()));
}
