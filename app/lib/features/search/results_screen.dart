import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/glyphs.dart';
import 'search_repository.dart';

class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key, required this.ingredients, this.text, this.mode = MatchMode.incl});
  final List<String> ingredients;
  final String? text;
  final MatchMode mode;

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  late var _q = SearchQuery(text: widget.text, ingredients: widget.ingredients, mode: widget.mode);

  bool get _byIngredient => widget.ingredients.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final res = ref.watch(searchProvider(_q));
    // Counts for the segmented control and the form pills ignore the form filter.
    final all = ref.watch(searchProvider(_q.copyWith(clearForm: true)));
    final counts = all.value;

    return Scaffold(
      body: Column(children: [
        HeroHeader(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              HeaderIconButton(icon: Icons.arrow_back_ios_new_rounded, label: 'Aramayı düzenle', onPressed: () => context.pop()),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (!_byIngredient)
                        Text('“${widget.text}”', style: displayStyle(22, color: Colors.white)),
                      for (var i = 0; i < widget.ingredients.length; i++) ...[
                        if (i > 0)
                          Text('+', style: displayStyle(22, color: Colors.white.withValues(alpha: 0.7))),
                        _HeaderChip(widget.ingredients[i]),
                      ],
                    ]),
                  ),
                ),
              ),
            ]),
            if (_byIngredient) ...[
              const SizedBox(height: 16),
              _Segmented(
                mode: _q.mode,
                incl: counts?.incl,
                exact: counts?.exact,
                onChanged: (m) => setState(() => _q = _q.copyWith(mode: m)),
              ),
            ],
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            color: EtkenColors.coral,
            onRefresh: () async => ref.invalidate(searchProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                if (counts != null) _forms(counts),
                const SizedBox(height: 14),
                ...res.when(
                  loading: () => const [Loading()],
                  error: (e, _) => [ErrorPanel(e, onRetry: () => ref.invalidate(searchProvider(_q)))],
                  data: _results,
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _forms(SearchResponse c) {
    final total = c.forms.values.fold(0, (a, b) => a + b);
    final groups = FormGroup.values.where((f) => (c.forms[f.name] ?? 0) > 0).toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        FilterPill(label: 'Tümü', count: total, selected: _q.form == null, onTap: () => setState(() => _q = _q.copyWith(clearForm: true))),
        for (final f in groups) ...[
          const SizedBox(width: 8),
          FilterPill(label: f.label, count: c.forms[f.name], selected: _q.form == f, onTap: () => setState(() => _q = _q.copyWith(form: f))),
        ],
      ]),
    );
  }

  List<Widget> _results(SearchResponse r) {
    if (r.items.isEmpty) {
      return [
        EmptyPanel(
          title: _byIngredient ? 'Bu bileşimde ürün yok' : 'Sonuç yok',
          body: _byIngredient
              ? (_q.mode == MatchMode.exact
                  ? '“İçeren ilaç” sekmesine geçin ya da form filtresini Tümü yapın.'
                  : 'Etken madde adını kontrol edin ya da form filtresini Tümü yapın.')
              : 'Ürün adını veya barkodu kontrol edin.',
        ),
      ];
    }
    final groups = groupEquivalents(r.items);
    final selected = widget.ingredients.map(baseIngredient).toSet();
    return [
      if (r.anySample) ...[const SampleBanner(), const SizedBox(height: 14)],
      for (final g in groups) ...[_GroupCard(group: g, selected: selected), const SizedBox(height: 14)],
      ProvenanceLine(r.items.first.provenance, prefix: 'İlaç listesi'),
      const SizedBox(height: 4),
      Text('Eşdeğer gruplar etken madde, miktar ve form birliğine göre oluşturulur; '
          'TİTCK eşdeğer kodu varsa o esas alınır.', style: bodyStyle(13, color: EtkenColors.muted)),
    ];
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = ingredientColor(name);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: c.color, borderRadius: BorderRadius.circular(999)),
      child: Align(widthFactor: 1, child: Text(name, style: displayStyle(19, color: c.onColor))),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.mode, required this.incl, required this.exact, required this.onChanged});
  final MatchMode mode;
  final int? incl;
  final int? exact;
  final ValueChanged<MatchMode> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Expanded(child: _seg('içeren ilaç', incl, MatchMode.incl)),
          const SizedBox(width: 4),
          Expanded(child: _seg('tam eşdeğer', exact, MatchMode.exact)),
        ]),
      );

  Widget _seg(String label, int? n, MatchMode m) {
    final on = mode == m;
    return Semantics(
      selected: on,
      button: true,
      child: Material(
        color: on ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onChanged(m),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            alignment: Alignment.centerLeft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(n?.toString() ?? '…', style: displayStyle(24, weight: FontWeight.w800, color: on ? EtkenColors.navy : Colors.white, height: 1)),
              const SizedBox(height: 4),
              Text(label, style: bodyStyle(14, weight: FontWeight.w600, color: on ? EtkenColors.navy : Colors.white)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.selected});
  final DrugGroup group;
  final Set<String> selected;

  @override
  Widget build(BuildContext context) {
    final d = group.representative;
    final extra = d.ingredients.map((i) => baseIngredient(i.name)).where((k) => !selected.contains(k)).toList();
    final tint = d.ingredients.isEmpty ? EtkenColors.bg : ingredientColor(baseIngredient(d.ingredients.first.name)).tint;
    final strength = d.strength ?? d.ingredients.map((i) => i.amountLabel).join(' + ');
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: EtkenColors.surface, borderRadius: BorderRadius.circular(EtkenRadius.card)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 68,
              height: 68,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(20)),
              child: PillGlyph.forDrug(d, size: 50),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(strength, style: displayStyle(23, color: EtkenColors.ink)),
                const SizedBox(height: 2),
                Text('${d.form ?? 'Form bilgisi yok'}, ${group.items.length} ürün', style: bodyStyle(15, color: EtkenColors.muted)),
              ]),
            ),
          ]),
        ),
        if (extra.isNotEmpty && selected.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: ingredientColor(extra.first).tint, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              IngredientDot(ingredientColor(extra.first).color, width: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Ayrıca '),
                  TextSpan(text: extra.join(', '), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' içerir'),
                ]), style: bodyStyle(14, color: EtkenColors.ink)),
              ),
            ]),
          ),
        for (final it in group.items) DrugRow(drug: it),
      ]),
    );
  }
}

/// One product row (brand, firm, pack, PSF) used across lists.
class DrugRow extends StatelessWidget {
  const DrugRow({super.key, required this.drug, this.trailing, this.onTap, this.divider = true});
  final Drug drug;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap ?? () => context.push('/ilac/${drug.id}'),
        child: Container(
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: divider ? const BoxDecoration(border: Border(top: BorderSide(color: EtkenColors.lineSoft))) : null,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text([drug.name, if (drug.strength != null && !drug.name.contains(drug.strength!)) drug.strength].join(' '),
                        style: bodyStyle(17, weight: FontWeight.w700, color: EtkenColors.ink, height: 1.25)),
                  ),
                  if (drug.recalled) ...[const SizedBox(width: 6), const RiskBadge(Severity.kritik, compact: true)],
                ]),
                Text([drug.firm ?? 'Firma bilgisi yok', if (drug.pack != null) drug.pack!].join(', '),
                    style: bodyStyle(14, color: EtkenColors.muted)),
              ]),
            ),
            const SizedBox(width: 8),
            trailing ??
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: EtkenColors.bg, borderRadius: BorderRadius.circular(10)),
                  child: Text(drug.psf == null ? 'PSF yok' : fmtPrice(drug.psf),
                      style: bodyStyle(14, weight: FontWeight.w600, color: EtkenColors.ink)),
                ),
            const Icon(Icons.chevron_right_rounded, color: EtkenColors.muted),
          ]),
        ),
      );
}
