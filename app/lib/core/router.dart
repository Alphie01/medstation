import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/announcements/announcements_screen.dart';
import '../features/assistant/assistant_screen.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/more/more_screen.dart';
import '../features/more/tenant_screens.dart';
import '../features/prescription/check_result_screen.dart';
import '../features/prescription/prescription_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/search/detail_screen.dart';
import '../features/search/home_screen.dart';
import '../features/search/results_screen.dart';
import '../features/stock/stock_repository.dart';
import '../features/stock/stock_screen.dart';
import '../features/tools/tools_screen.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';
import 'widgets/common.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Rebuilds the router's redirect when auth state changes.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthListenable(ref);
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/ara',
    refreshListenable: refresh,
    redirect: (_, s) {
      final status = ref.read(authProvider).status;
      final at = s.matchedLocation;
      return switch (status) {
        AuthStatus.loading => at == '/acilis' ? null : '/acilis',
        AuthStatus.signedOut => at == '/giris' ? null : '/giris',
        AuthStatus.locked => at == '/kilit' ? null : '/kilit',
        AuthStatus.signedIn => (at == '/giris' || at == '/kilit' || at == '/acilis') ? '/ara' : null,
      };
    },
    routes: [
      GoRoute(path: '/acilis', builder: (_, _) => const Scaffold(body: Loading())),
      GoRoute(path: '/giris', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/kilit', builder: (_, _) => const LockScreen()),
      GoRoute(
        path: '/tara',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ScanScreen(
          target: switch (s.uri.queryParameters['hedef']) {
            'recete' => ScanTarget.prescription,
            'stok' => ScanTarget.stock,
            _ => ScanTarget.detail,
          },
          direction: s.uri.queryParameters['yon'] == 'cikis' ? StockDirection.cikis : StockDirection.giris,
        ),
      ),
      GoRoute(path: '/ilac/:id', parentNavigatorKey: _rootKey, builder: (_, s) => DetailScreen(id: s.pathParameters['id']!)),
      GoRoute(
        path: '/ara/sonuclar',
        parentNavigatorKey: _rootKey,
        builder: (_, s) {
          final q = s.uri.queryParameters;
          return ResultsScreen(
            ingredients: (q['i'] ?? '').split(',').where((e) => e.isNotEmpty).toList(),
            text: q['q'],
            mode: q['m'] == 'exact' ? MatchMode.exact : MatchMode.incl,
          );
        },
      ),
      GoRoute(path: '/recete/sonuc', parentNavigatorKey: _rootKey, builder: (_, _) => const CheckResultScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => _Shell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/ara', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/recete', builder: (_, _) => const PrescriptionScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/asistan',
              builder: (_, s) => AssistantScreen(
                drugId: s.uri.queryParameters['drug'],
                drugName: s.uri.queryParameters['name'],
                question: s.uri.queryParameters['q'],
              ),
            ),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/stok', builder: (_, _) => const StockScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/daha', builder: (_, _) => const MoreScreen(), routes: [
              GoRoute(path: 'araclar', builder: (_, _) => const ToolsScreen(), routes: [
                GoRoute(path: ':tool', builder: (_, s) => ToolScreen(id: s.pathParameters['tool']!)),
              ]),
              GoRoute(path: 'duyurular', builder: (_, _) => const AnnouncementsScreen()),
              GoRoute(path: 'favoriler', builder: (_, _) => const FavoritesScreen()),
              GoRoute(path: 'kaynaklar', builder: (_, _) => const SourcesScreen()),
              GoRoute(path: 'gizlilik', builder: (_, _) => const PrivacyScreen()),
              GoRoute(path: 'katalog', builder: (_, _) => const CatalogScreen()),
              GoRoute(path: 'kullanicilar', builder: (_, _) => const UsersScreen()),
            ]),
          ]),
        ],
      ),
    ],
  );
});

class _Shell extends StatelessWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;

  static const _items = [
    (Icons.search_rounded, 'Ara'),
    (Icons.receipt_long_rounded, 'Reçete'),
    (Icons.auto_awesome_outlined, 'Asistan'),
    (Icons.inventory_2_outlined, 'Stok'),
    (Icons.grid_view_rounded, 'Daha fazla'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: shell,
        bottomNavigationBar: SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: EtkenColors.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: EtkenColors.navy.withValues(alpha: 0.14), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: Row(children: [
              for (final (i, (icon, label)) in _items.indexed)
                Expanded(
                  child: Semantics(
                    selected: shell.currentIndex == i,
                    button: true,
                    label: label,
                    excludeSemantics: true,
                    child: Material(
                      color: shell.currentIndex == i ? EtkenColors.navy : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                        child: SizedBox(
                          height: 56,
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(icon, size: 22, color: shell.currentIndex == i ? Colors.white : EtkenColors.muted),
                            const SizedBox(height: 2),
                            Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false,
                                style: bodyStyle(11, weight: FontWeight.w600, color: shell.currentIndex == i ? Colors.white : EtkenColors.muted)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
}
