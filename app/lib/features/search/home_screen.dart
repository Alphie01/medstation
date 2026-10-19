import 'dart:async';

import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/glyphs.dart';
import 'search_repository.dart';

/// Ingredients being composed on the home screen.
class SearchDraft extends Notifier<List<String>> {
  @override
  List<String> build() => const [];
  void add(String i) {
    if (!state.contains(i)) state = [...state, i];
  }

  void remove(String i) => state = state.where((x) => x != i).toList();
  void set(List<String> v) => state = List.of(v);
  void clear() => state = const [];
}

final searchDraftProvider = NotifierProvider<SearchDraft, List<String>>(SearchDraft.new);

String resultsLocation({List<String> ingredients = const [], String? text, MatchMode mode = MatchMode.incl}) =>
    Uri(path: '/ara/sonuclar', queryParameters: {
      if (ingredients.isNotEmpty) 'i': ingredients.join(','),
      if (text != null) 'q': text,
      if (mode == MatchMode.exact) 'm': 'exact',
    }).toString();

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<IngredientHit> _suggestions = const [];
  int _hi = 0;
  bool _loadingSuggest = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _hi = 0);
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      setState(() => _loadingSuggest = true);
      try {
        final r = await ref.read(searchRepositoryProvider).suggest(q);
        if (!mounted || _input.text.trim() != q) return;
        final chips = ref.read(searchDraftProvider);
        setState(() => _suggestions = r.where((h) => !chips.contains(h.name)).toList());
      } catch (_) {
        if (mounted) setState(() => _suggestions = const []);
      } finally {
        if (mounted) setState(() => _loadingSuggest = false);
      }
    });
  }

  void _add(String name) {
    ref.read(searchDraftProvider.notifier).add(name);
    _input.clear();
    setState(() => _suggestions = const []);
    _focus.requestFocus();
  }

  void _showResults() {
    final chips = ref.read(searchDraftProvider);
    if (chips.isEmpty) return;
    ref.read(recentSearchesProvider.notifier).add(chips);
    context.push(resultsLocation(ingredients: chips));
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final chips = ref.read(searchDraftProvider);
    if (e.logicalKey == LogicalKeyboardKey.arrowDown && _suggestions.isNotEmpty) {
      setState(() => _hi = (_hi + 1) % _suggestions.length);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp && _suggestions.isNotEmpty) {
      setState(() => _hi = (_hi - 1 + _suggestions.length) % _suggestions.length);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace && _input.text.isEmpty && chips.isNotEmpty) {
      ref.read(searchDraftProvider.notifier).remove(chips.last);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onSubmitted(String v) {
    if (_suggestions.isNotEmpty) {
      _add(_suggestions[_hi.clamp(0, _suggestions.length - 1)].name);
    } else if (v.trim().isNotEmpty) {
      // No ingredient matched: search by product name or barcode.
      context.push(resultsLocation(text: v.trim()));
    } else {
      _showResults();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chips = ref.watch(searchDraftProvider);
    final typing = _input.text.trim().isNotEmpty;
    final count = chips.isEmpty ? null : ref.watch(searchProvider(SearchQuery(ingredients: chips)));
    final meta = ref.watch(metaProvider).value;

    return Scaffold(
      body: Stack(children: [
        ListView(
          padding: EdgeInsets.only(bottom: chips.isEmpty ? 28 : 110),
          children: [
            HeroHeader(
              decor: true,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 84),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: EtkenColors.coral, borderRadius: BorderRadius.circular(11)),
                    child: Text('m', style: displayStyle(21, weight: FontWeight.w800, color: EtkenColors.ink, height: 1)),
                  ),
                  const SizedBox(width: 10),
                  Text('medstation', style: displayStyle(22, color: Colors.white)),
                  const Spacer(),
                  HeaderIconButton(icon: Icons.qr_code_scanner_rounded, label: 'Karekod okut', size: 48, onPressed: () => context.push('/tara')),
                ]),
                const SizedBox(height: 60),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 250),
                  child: Semantics(
                    header: true,
                    child: Text('Etken maddeyi yaz, ilaçlar gelsin.',
                        style: displayStyle(40, weight: FontWeight.w800, color: Colors.white, height: 0.98)),
                  ),
                ),
              ]),
            ),
            Transform.translate(
              offset: const Offset(0, -52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _searchCard(chips),
              ),
            ),
            if (!typing)
              Transform.translate(
                offset: const Offset(0, -52),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _popular(chips),
                  _recents(),
                  if (meta != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (meta.anySample) ...[const SampleBanner(), const SizedBox(height: 10)],
                        ProvenanceLine(_drugSource(meta), prefix: 'İlaç listesi'),
                      ]),
                    ),
                ]),
              ),
          ],
        ),
        if (chips.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: CtaButton(
              label: 'İlaçları göster',
              badge: count?.value?.incl.toString() ?? '…',
              onPressed: _showResults,
            ),
          ),
      ]),
    );
  }

  Widget _searchCard(List<String> chips) => Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: EtkenColors.surface,
          borderRadius: BorderRadius.circular(EtkenRadius.card),
          boxShadow: [BoxShadow(color: EtkenColors.navy.withValues(alpha: 0.2), blurRadius: 44, offset: const Offset(0, 22))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Etken madde, ilaç adı veya barkod', style: bodyStyle(13, weight: FontWeight.w600, color: EtkenColors.muted)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final c in chips) _Chip(name: c, onRemove: () => ref.read(searchDraftProvider.notifier).remove(c)),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 120, maxWidth: 400),
              child: IntrinsicWidth(
                child: Focus(
                  onKeyEvent: _onKey,
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    onChanged: _onChanged,
                    onSubmitted: _onSubmitted,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    enableSuggestions: false,
                    cursorColor: EtkenColors.coral,
                    style: bodyStyle(19, weight: FontWeight.w500, color: EtkenColors.ink),
                    decoration: InputDecoration(
                      hintText: chips.isEmpty ? 'örn. amoksisilin' : 'madde ekle',
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                    ),
                  ),
                ),
              ),
            ),
          ]),
          if (_input.text.trim().isNotEmpty) ...[
            const Divider(height: 18),
            if (_loadingSuggest && _suggestions.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(color: EtkenColors.coral)),
            for (var i = 0; i < _suggestions.length; i++) _suggestionRow(_suggestions[i], i == _hi),
            _nameSearchRow(),
          ],
        ]),
      );

  Widget _suggestionRow(IngredientHit h, bool hi) {
    final q = searchFold(_input.text);
    final starts = searchFold(h.name).startsWith(q);
    return Material(
      color: hi ? EtkenColors.bg : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _add(h.name),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            IngredientDot(ingredientColor(h.name).color, width: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  if (starts) TextSpan(text: h.name.substring(0, q.length.clamp(0, h.name.length)), style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: starts ? h.name.substring(q.length.clamp(0, h.name.length)) : h.name),
                ]),
                style: bodyStyle(18, color: EtkenColors.ink),
              ),
            ),
            Text('${h.productCount} ürün', style: bodyStyle(14, color: EtkenColors.muted)),
          ]),
        ),
      ),
    );
  }

  Widget _nameSearchRow() => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push(resultsLocation(text: _input.text.trim())),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            const Icon(Icons.search_rounded, color: EtkenColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text('“${_input.text.trim()}” adıyla veya barkoduyla ara',
                  style: bodyStyle(16, color: EtkenColors.muted)),
            ),
          ]),
        ),
      );

  Widget _popular(List<String> chips) {
    final frequent = ref.read(recentSearchesProvider.notifier).frequent();
    final top = ref.watch(topIngredientsProvider);
    final usingHistory = frequent.length >= 3;
    final names = usingHistory ? frequent : (top.value ?? const []).map((h) => h.name).toList();
    final counts = {for (final h in top.value ?? const <IngredientHit>[]) h.name: h.productCount};
    final shown = names.where((n) => !chips.contains(n)).take(8).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(usingHistory ? 'Sık aradıklarınız' : 'En çok ürünü olan maddeler',
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 14)),
      SizedBox(
        height: 172,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: shown.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final n = shown[i];
            final c = ingredientColor(n);
            return _PopularCard(name: n, color: c, count: counts[n], onTap: () => _add(n));
          },
        ),
      ),
    ]);
  }

  Widget _recents() {
    final recents = ref.watch(recentSearchesProvider);
    if (recents.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Son aramalar', padding: const EdgeInsets.fromLTRB(4, 30, 4, 14)),
        EtkenCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            for (var i = 0; i < recents.take(5).length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              _RecentRow(r: recents[i], onTap: () {
                ref.read(searchDraftProvider.notifier).set(recents[i].ingredients);
                ref.read(recentSearchesProvider.notifier).add(recents[i].ingredients);
                context.push(resultsLocation(ingredients: recents[i].ingredients));
              }),
            ],
          ]),
        ),
      ]),
    );
  }

  DataProvenance? _drugSource(Meta m) {
    final s = m.source('drugs');
    if (s == null) return null;
    return DataProvenance(
      source: s['source'] as String,
      version: s['version'] as String,
      fetchedAt: DateTime.parse(s['fetchedAt'] as String),
      isSample: s['isSample'] as bool,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.name, required this.onRemove});
  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = ingredientColor(name);
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 12, right: 2),
      decoration: BoxDecoration(color: c.tint, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IngredientDot(c.color),
        const SizedBox(width: 8),
        Text(name, style: bodyStyle(16, weight: FontWeight.w600, color: EtkenColors.ink)),
        IconButton(
          onPressed: onRemove,
          tooltip: '$name çıkar',
          iconSize: 16,
          icon: const Icon(Icons.close_rounded, color: EtkenColors.ink),
        ),
      ]),
    );
  }
}

class _PopularCard extends StatelessWidget {
  const _PopularCard({required this.name, required this.color, required this.count, required this.onTap});
  final String name;
  final IngredientColor color;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: color.color,
        borderRadius: BorderRadius.circular(EtkenRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 146,
            child: Stack(children: [
              Positioned(
                right: -18,
                top: 22,
                child: PillGlyph(a: Colors.white.withValues(alpha: 0.92), b: Colors.white.withValues(alpha: 0.5), size: 104, shadow: false),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(count == null ? '' : '$count ürün',
                      style: bodyStyle(14, weight: FontWeight.w600, color: color.onColor.withValues(alpha: 0.9))),
                  name.contains(' ')
                      ? Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: displayStyle(22, color: color.onColor, height: 1.02))
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomLeft,
                          child: Text(name, maxLines: 1, style: displayStyle(22, color: color.onColor, height: 1.02)),
                        ),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.r, required this.onTap});
  final RecentSearch r;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = ingredientColor(r.ingredients.first).color;
    final b = ingredientColor(r.ingredients.length > 1 ? r.ingredients[1] : r.ingredients.first).color;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: EtkenColors.bg, borderRadius: BorderRadius.circular(15)),
            child: PillGlyph(a: a, b: b, size: 32, shadow: false),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.ingredients.join(' + '), style: bodyStyle(17, weight: FontWeight.w600, color: EtkenColors.ink, height: 1.25)),
              Text(fmtDateTime(r.at), style: bodyStyle(14, color: EtkenColors.muted)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: EtkenColors.muted),
        ]),
      ),
    );
  }
}
