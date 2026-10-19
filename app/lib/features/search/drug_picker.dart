import 'dart:async';

import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import 'results_screen.dart';
import 'search_repository.dart';

/// Bottom sheet to pick one product by name, barcode or ingredient.
Future<Drug?> pickDrug(BuildContext context, {String? initial, String title = 'İlaç ekle'}) =>
    showModalBottomSheet<Drug>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: EtkenColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (_) => _DrugPicker(initial: initial, title: title),
    );

class _DrugPicker extends ConsumerStatefulWidget {
  const _DrugPicker({this.initial, required this.title});
  final String? initial;
  final String title;
  @override
  ConsumerState<_DrugPicker> createState() => _DrugPickerState();
}

class _DrugPickerState extends ConsumerState<_DrugPicker> {
  late final _c = TextEditingController(text: widget.initial);
  Timer? _t;
  List<Drug>? _items;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if ((widget.initial ?? '').trim().isNotEmpty) _search(widget.initial!);
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 250), () => _search(v));
  }

  Future<void> _search(String v) async {
    final q = v.trim();
    if (q.length < 2) {
      setState(() => _items = null);
      return;
    }
    setState(() => _loading = true);
    try {
      final repo = ref.read(searchRepositoryProvider);
      var r = await repo.search(SearchQuery(text: q));
      if (r.items.isEmpty) r = await repo.search(SearchQuery(ingredients: [q]));
      if (mounted && _c.text.trim() == q) setState(() => (_items = r.items, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          builder: (_, scroll) => Column(children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: EtkenColors.lineStrong, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: displayStyle(22, color: EtkenColors.ink)),
                const SizedBox(height: 10),
                TextField(
                  controller: _c,
                  autofocus: widget.initial == null,
                  onChanged: _onChanged,
                  decoration: const InputDecoration(
                    hintText: 'İlaç adı, barkod veya etken madde',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ]),
            ),
            if (_loading) const LinearProgressIndicator(color: EtkenColors.coral),
            Expanded(
              child: _error != null
                  ? ErrorPanel(_error!)
                  : _items == null
                      ? const SizedBox.shrink()
                      : _items!.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: EmptyPanel(title: 'Sonuç yok', body: 'Adı veya barkodu kontrol edin.'),
                            )
                          : ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                              EtkenCard(
                                padding: EdgeInsets.zero,
                                child: Column(children: [
                                  for (var i = 0; i < _items!.length; i++)
                                    DrugRow(
                                      drug: _items![i],
                                      divider: i > 0,
                                      trailing: const Icon(Icons.add_circle_outline_rounded, color: EtkenColors.navy),
                                      onTap: () => Navigator.pop(context, _items![i]),
                                    ),
                                ]),
                              ),
                            ]),
            ),
          ]),
        ),
      );
}
