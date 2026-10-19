import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/glyphs.dart';
import '../prescription/prescription_draft.dart';
import 'home_screen.dart';
import 'search_repository.dart';

class DetailScreen extends ConsumerWidget {
  const DetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(drugProvider(id));
    return Scaffold(
      body: d.when(
        loading: () => const Loading(),
        error: (e, _) => SafeArea(
          child: Column(children: [
            Align(alignment: Alignment.centerLeft, child: BackButton(onPressed: () => context.pop())),
            ErrorPanel(e, onRetry: () => ref.invalidate(drugProvider(id))),
          ]),
        ),
        data: (drug) => _Detail(drug: drug),
      ),
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({required this.drug});
  final Drug drug;
  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  bool? _fav;

  Future<void> _toggleFav(bool current) async {
    final next = !current;
    setState(() => _fav = next);
    try {
      await ref.read(searchRepositoryProvider).setFavorite(widget.drug.id, next);
      ref.invalidate(favoritesProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _fav = current);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Favori güncellenemedi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.drug;
    final eq = ref.watch(equivalentsProvider(d.id));
    final favs = ref.watch(favoritesProvider).value;
    final isFav = _fav ?? favs?.any((f) => f.id == d.id) ?? false;
    final total = d.ingredients.fold<double>(0, (a, i) => a + (i.amount ?? 0));

    return Stack(children: [
      ListView(padding: const EdgeInsets.only(bottom: 104), children: [
        HeroHeader(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              HeaderIconButton(icon: Icons.arrow_back_ios_new_rounded, label: 'Geri', onPressed: () => context.pop()),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                child: Text(d.rxType.label, style: bodyStyle(14, weight: FontWeight.w600, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              HeaderIconButton(
                icon: isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                label: isFav ? 'Favorilerden çıkar' : 'Favorilere ekle',
                onPressed: () => _toggleFav(isFav),
              ),
            ]),
            SizedBox(
              height: 176,
              child: Center(
                child: Stack(alignment: Alignment.center, children: [
                  Container(width: 168, height: 168, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), shape: BoxShape.circle)),
                  PillGlyph.forDrug(d, size: 150),
                ]),
              ),
            ),
            Semantics(header: true, child: Text(d.name, style: displayStyle(44, weight: FontWeight.w800, color: Colors.white, height: 0.95))),
            const SizedBox(height: 8),
            Text([d.strength, d.form?.toLowerCase(), d.firm].whereType<String>().join(', '),
                style: bodyStyle(17, color: Colors.white.withValues(alpha: 0.82))),
          ]),
        ),
        if (d.provenance.isSample) const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 0), child: SampleBanner()),
        if (d.licenseStatus.suspended)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: EtkenCard(
              color: d.licenseStatus == LicenseStatus.farmakovijilansAskida ? EtkenColors.riskCriticalTint : EtkenColors.riskMajorTint,
              child: Row(children: [
                RiskBadge(d.licenseStatus == LicenseStatus.farmakovijilansAskida ? Severity.kritik : Severity.onemli),
                const SizedBox(width: 10),
                Expanded(child: Text('${d.licenseStatus.label}. Vermeden önce güncel durumu kontrol edin.', style: bodyStyle(15))),
              ]),
            ),
          ),
        if (d.recalled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: EtkenCard(
              color: EtkenColors.riskCriticalTint,
              child: Row(children: [
                const RiskBadge(Severity.kritik),
                const SizedBox(width: 10),
                Expanded(child: Text('Bu ürün geri çekilenler listesinde. Duyurular bölümünü kontrol edin.', style: bodyStyle(15))),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: EtkenCard(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bileşim', style: displayStyle(19, color: EtkenColors.ink)),
              const SizedBox(height: 14),
              if (d.ingredients.isEmpty)
                Text(d.compositionText == null ? 'Etken madde bilgisi yok' : 'Bileşim ayrıştırılamadı; kaynaktaki metin aşağıda. Etkileşim ve doz kontrolleri bu ürün için yapılamaz.',
                    style: bodyStyle(15, color: EtkenColors.muted))
              else ...[
                if (total > 0)
                  ExcludeSemantics(
                    child: SizedBox(
                      height: 18,
                      child: Row(children: [
                        for (var i = 0; i < d.ingredients.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Expanded(
                            flex: ((d.ingredients[i].amount ?? 0) / total * 100).round().clamp(6, 100),
                            child: Container(
                              decoration: BoxDecoration(
                                color: ingredientColor(baseIngredient(d.ingredients[i].name)).color,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ),
                const SizedBox(height: 14),
                for (final i in d.ingredients)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      IngredientDot(ingredientColor(baseIngredient(i.name)).color),
                      const SizedBox(width: 10),
                      Expanded(child: Text(i.name, style: bodyStyle(16))),
                      Text(i.amountLabel, style: bodyStyle(16, weight: FontWeight.w700, color: i.amount == null ? EtkenColors.muted : EtkenColors.ink)),
                    ]),
                  ),
              ],
              if (d.compositionText != null) ...[
                const SizedBox(height: 10),
                Text('Kaynaktaki bileşim: ${d.compositionText}', style: bodyStyle(13, color: EtkenColors.muted)),
              ],
              if (d.ingredients.isNotEmpty && d.ingredients.any((i) => i.amount == null)) ...[
                const SizedBox(height: 6),
                Text('Kombine üründe madde miktarları kaynakta ayrı verilmediği için gösterilmiyor; doz kontrolü bu ürün için yapılamaz.',
                    style: bodyStyle(13, color: EtkenColors.muted)),
              ],
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _FactsGrid(facts: [
            ('Fiyat (PSF)', d.psf == null ? null : fmtPrice(d.psf)),
            ('SGK ödemesi', d.sgkStatus),
            ('Ambalaj', d.pack),
            ('ATC kodu', d.atc),
            ('Barkod', d.barcode),
            ('Eşdeğer kodu', d.equivalenceCode),
            ('Saklama koşulları', d.storage),
            ('Piyasa durumu (SKRS)', d.marketStatus == MarketStatus.bilinmiyor ? null : d.marketStatus.label),
            ('Ruhsat', d.licenseStatus == LicenseStatus.bilinmiyor ? null : d.licenseStatus.label),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(child: _DocButton(label: 'KÜB', url: d.kubUrl)),
            const SizedBox(width: 10),
            Expanded(child: _DocButton(label: 'KT', url: d.ktUrl)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 52)),
                onPressed: () {
                  ref.read(prescriptionDraftProvider.notifier).addDrug(d);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${d.name} reçeteye eklendi'),
                    action: SnackBarAction(label: 'Reçete', onPressed: () => context.go('/recete')),
                  ));
                },
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('Reçeteye ekle'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 52)),
                onPressed: () => context.go('/asistan?drug=${Uri.encodeComponent(d.id)}&name=${Uri.encodeComponent(d.name)}'),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Asistana sor'),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SectionTitle(eq.value == null ? 'Eşdeğerler' : (eq.value!.isEmpty ? 'Eşdeğerler' : '${eq.value!.length} eşdeğer ürün')),
        ),
        SizedBox(
          height: 140,
          child: eq.when(
            loading: () => const Loading(),
            error: (e, _) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text('$e')),
            data: (items) => items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text('Bu doz ve formda başka ürün yok.', style: bodyStyle(15, color: EtkenColors.muted)),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _EquivCard(items[i]),
                  ),
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 0), child: ProvenanceLine(d.provenance)),
      ]),
      Positioned(
        left: 16,
        right: 16,
        bottom: 18,
        child: SafeArea(
          top: false,
          child: CtaButton(
            coral: true,
            label: 'Bu bileşimdeki tüm ilaçlar',
            onPressed: d.ingredients.isEmpty
                ? null
                : () {
                    final ings = d.ingredients.map((i) => baseIngredient(i.name)).toSet().toList();
                    ref.read(searchDraftProvider.notifier).set(ings);
                    context.push(resultsLocation(ingredients: ings, mode: MatchMode.exact));
                  },
          ),
        ),
      ),
    ]);
  }
}

class _FactsGrid extends StatelessWidget {
  const _FactsGrid({required this.facts});
  final List<(String, String?)> facts;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final (label, value) in facts)
            SizedBox(
              width: (value?.length ?? 0) > 18 ? c.maxWidth : w,
              child: EtkenCard(
                radius: EtkenRadius.tile,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Semantics(
                  label: '$label: ${value ?? 'Veri yok'}',
                  excludeSemantics: true,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: bodyStyle(13, color: EtkenColors.muted)),
                    const SizedBox(height: 2),
                    Text(value ?? 'Veri yok',
                        style: bodyStyle(17, weight: FontWeight.w700, color: value == null ? EtkenColors.muted : EtkenColors.ink)),
                  ]),
                ),
              ),
            ),
        ]);
      });
}

class _DocButton extends StatelessWidget {
  const _DocButton({required this.label, required this.url});
  final String label;
  final String? url;

  @override
  Widget build(BuildContext context) => EtkenCard(
        radius: EtkenRadius.tile,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: url == null ? null : () => launchUrl(Uri.parse(url!), mode: LaunchMode.inAppBrowserView),
        child: Row(children: [
          Icon(Icons.description_outlined, color: url == null ? EtkenColors.placeholder : EtkenColors.navy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: bodyStyle(16, weight: FontWeight.w700)),
              Text(url == null ? 'Belge bağlı değil' : 'TİTCK belgesini aç', style: bodyStyle(13, color: EtkenColors.muted)),
            ]),
          ),
        ]),
      );
}

class _EquivCard extends StatelessWidget {
  const _EquivCard(this.d);
  final Drug d;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 168,
        child: EtkenCard(
          radius: EtkenRadius.cta,
          padding: const EdgeInsets.all(14),
          onTap: () => context.push('/ilac/${d.id}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Padding(padding: const EdgeInsets.only(top: 8, left: 2), child: PillGlyph.forDrug(d, size: 40)),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: bodyStyle(17, weight: FontWeight.w700, height: 1.2)),
              Text('${d.firm ?? 'Firma yok'}, ${d.psf == null ? 'PSF yok' : fmtPrice(d.psf)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(14, color: EtkenColors.muted)),
            ]),
          ]),
        ),
      );
}
