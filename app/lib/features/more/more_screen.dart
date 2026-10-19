import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_controller.dart';
import '../search/results_screen.dart';
import '../search/search_repository.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    Widget tile(IconData i, String t, String s, String path) => ListTile(
          minVerticalPadding: 14,
          leading: Icon(i, color: EtkenColors.navy),
          title: Text(t, style: bodyStyle(16, weight: FontWeight.w700)),
          subtitle: Text(s, style: bodyStyle(14, color: EtkenColors.muted)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(path),
        );
    return Scaffold(
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        HeroHeader(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text('Daha fazla', style: displayStyle(30, weight: FontWeight.w800, color: Colors.white))),
            const SizedBox(height: 6),
            Text('${auth.fullName} · ${auth.role}', style: bodyStyle(15, color: Colors.white.withValues(alpha: 0.8))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: EtkenCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              tile(Icons.calculate_outlined, 'Araçlar', 'Doz, pediatrik doz, birim, majistral, karşılaştırma', '/daha/araclar'),
              const Divider(height: 1),
              tile(Icons.campaign_outlined, 'Duyurular', 'TİTCK duyuruları, geri çekmeler, güvenlilik, fiyat', '/daha/duyurular'),
              const Divider(height: 1),
              tile(Icons.star_outline_rounded, 'Favoriler', 'Kaydettiğiniz ilaçlar', '/daha/favoriler'),
              const Divider(height: 1),
              tile(Icons.storefront_outlined, 'Destekleyici ürünler', 'Eczanenizin ticari ürün kataloğu (klinik öneriden ayrı)', '/daha/katalog'),
              if (auth.role == 'eczaci' || auth.role == 'admin') ...[
                const Divider(height: 1),
                tile(Icons.group_outlined, 'Eczane kullanıcıları', 'Aynı eczanede çalışan hesaplar ve roller', '/daha/kullanicilar'),
              ],
              const Divider(height: 1),
              tile(Icons.dataset_outlined, 'Veri kaynakları', 'Bağlı veri setleri, sürümler ve güncellemeler', '/daha/kaynaklar'),
              const Divider(height: 1),
              tile(Icons.shield_outlined, 'Gizlilik ve güvenlik', 'KVKK, biyometrik kilit, oturum', '/daha/gizlilik'),
            ]),
          ),
        ),
      ]),
    );
  }
}

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(favoritesProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Favoriler', style: displayStyle(22, color: EtkenColors.ink)), backgroundColor: EtkenColors.bg),
      body: f.when(
        loading: () => const Loading(),
        error: (e, _) => ErrorPanel(e, onRetry: () => ref.invalidate(favoritesProvider)),
        data: (items) => ListView(padding: const EdgeInsets.all(16), children: [
          if (items.isEmpty)
            const EmptyPanel(title: 'Favori yok', body: 'İlaç detayında yıldıza dokunarak sık kullandığınız ilaçları kaydedin.')
          else
            EtkenCard(
              padding: EdgeInsets.zero,
              child: Column(children: [for (final (i, d) in items.indexed) DrugRow(drug: d, divider: i > 0)]),
            ),
        ]),
      ),
    );
  }
}

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  static const _kinds = {
    'drugs': 'İlaç listesi',
    'interactions': 'Etkileşim veritabanı',
    'dose_limits': 'Doz sınırları',
    'documents': 'KÜB/KT belgeleri',
    'announcements': 'TİTCK duyuruları',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(metaProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Veri kaynakları', style: displayStyle(22, color: EtkenColors.ink)), backgroundColor: EtkenColors.bg),
      body: m.when(
        loading: () => const Loading(),
        error: (e, _) => ErrorPanel(e, onRetry: () => ref.invalidate(metaProvider)),
        data: (m) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(metaProvider),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (m.anySample) ...[const SampleBanner(), const SizedBox(height: 12)],
            for (final e in _kinds.entries) ...[
              EtkenCard(
                child: Builder(builder: (_) {
                  final s = m.source(e.key);
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(e.value, style: bodyStyle(16, weight: FontWeight.w700))),
                      Icon(s == null ? Icons.link_off_rounded : Icons.check_circle_outline_rounded,
                          color: s == null ? EtkenColors.muted : EtkenColors.commercial),
                      const SizedBox(width: 4),
                      Text(s == null ? 'Bağlı değil' : 'Bağlı', style: bodyStyle(13, weight: FontWeight.w700)),
                    ]),
                    if (s != null) ...[
                      const SizedBox(height: 6),
                      Text('${s['source']} · sürüm ${s['version']}', style: bodyStyle(14)),
                      Text('Son güncelleme ${fmtDateTime(DateTime.parse(s['fetchedAt'] as String))}'
                          '${s['rowCount'] == null ? '' : ' · ${s['rowCount']} kayıt'}'
                          '${(s['skipped'] ?? 0) == 0 ? '' : ' · ${s['skipped']} satır atlandı'}',
                          style: bodyStyle(13, color: EtkenColors.muted)),
                    ] else if (e.key == 'interactions') ...[
                      const SizedBox(height: 6),
                      Text('Reçete kontrolünde etkileşimler "doğrulanamadı" olarak gösterilir; etkileşim yok anlamına gelmez.',
                          style: bodyStyle(13, color: EtkenColors.muted)),
                    ],
                  ]);
                }),
              ),
              const SizedBox(height: 10),
            ],
            EtkenCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Entegrasyonlar', style: bodyStyle(16, weight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('MEDULA e-Reçete: ${m.medulaAvailable ? 'yetkili entegrasyon etkin' : 'yetkilendirilmemiş'}', style: bodyStyle(14)),
                Text('AI asistan: ${m.assistantAvailable ? 'etkin' : 'yapılandırılmamış'}', style: bodyStyle(14)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});
  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text('Gizlilik ve güvenlik', style: displayStyle(22, color: EtkenColors.ink)), backgroundColor: EtkenColors.bg),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        EtkenCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SwitchListTile(
            title: Text('Biyometrik kilit', style: bodyStyle(16, weight: FontWeight.w700)),
            subtitle: Text('Uygulama açılışında Face ID / parmak izi iste', style: bodyStyle(14, color: EtkenColors.muted)),
            value: auth.biometricEnabled,
            onChanged: (v) async {
              try {
                await auth.setBiometric(v);
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
              }
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 12),
        EtkenCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('KVKK aydınlatma özeti', style: bodyStyle(16, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final s in const [
              'Hasta adı, T.C. kimlik no veya iletişim bilgisi istenmez ve saklanmaz.',
              'Reçete kontrollerinde yalnızca ilaçlar, kullanım talimatı, yaş ve kilo kaydedilir; kayıtlar saklama süresi sonunda silinir.',
              'Reçete fotoğrafları cihaz üzerinde okunur, sunucuya gönderilmez.',
              'AI asistana gönderilen sorulardan kimlik bilgileri sunucuda otomatik olarak çıkarılır.',
              'Oturum anahtarları cihazın güvenli anahtar deposunda tutulur; tüm trafik şifrelidir.',
              'Klinik kararlarınız denetim kaydına kullanıcı ve zaman bilgisiyle yazılır.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 6, color: EtkenColors.muted)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s, style: bodyStyle(14))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          onPressed: () {
            ref.read(recentSearchesProvider.notifier).clear();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihazdaki arama geçmişi silindi')));
          },
          icon: const Icon(Icons.history_toggle_off_rounded),
          label: const Text('Cihazdaki arama geçmişini sil'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: EtkenColors.riskCritical),
          onPressed: () => auth.logout(),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Çıkış yap'),
        ),
      ]),
    );
  }
}
