import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../search/drug_picker.dart';
import 'stock_repository.dart';

// Text scale for this dense, list-heavy screen.
TextStyle _title() => bodyStyle(15, weight: FontWeight.w700, height: 1.25);
TextStyle _meta() => bodyStyle(13, color: EtkenColors.muted);
TextStyle _section() => displayStyle(18, color: EtkenColors.ink);

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});
  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  int _tab = 0;

  void _refresh() {
    ref.invalidate(stockListProvider);
    ref.invalidate(stockAlertsProvider);
    ref.invalidate(stockMovementsProvider);
  }

  Future<void> _scan(StockDirection d) async {
    await context.push('/tara?hedef=stok&yon=${d.name}');
    _refresh();
  }

  Future<void> _addManual() async {
    final d = await pickDrug(context, title: 'Stoğa ilaç ekle');
    if (d == null || !mounted) return;
    final r = await showDialog<_BatchInput>(
      context: context,
      builder: (_) => _BatchDialog(drug: d),
    );
    if (r == null) return;
    try {
      final repo = ref.read(stockRepositoryProvider);
      final item = await repo.addItem(d.id, r.critical);
      if (r.quantity > 0) await repo.addBatch(item.id, lot: r.lot, expiry: r.expiry, quantity: r.quantity);
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        HeroHeader(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Stok ve SKT',
                        style: displayStyle(28, weight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ),
                  HeaderIconButton(icon: Icons.edit_note_rounded, label: 'Elle ekle', onPressed: _addManual),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ScanButton(direction: StockDirection.giris, onTap: () => _scan(StockDirection.giris)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ScanButton(direction: StockDirection.cikis, onTap: () => _scan(StockDirection.cikis)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    for (final (i, l) in const [(0, 'Uyarılar'), (1, 'Stok'), (2, 'Hareketler')])
                      Expanded(
                        child: Semantics(
                          selected: _tab == i,
                          button: true,
                          child: Material(
                            color: _tab == i ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setState(() => _tab = i),
                              child: Container(
                                height: 44,
                                alignment: Alignment.center,
                                child: Text(
                                  l,
                                  style: bodyStyle(
                                    14,
                                    weight: FontWeight.w700,
                                    color: _tab == i ? EtkenColors.navy : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: EtkenColors.coral,
            onRefresh: () async => _refresh(),
            child: switch (_tab) {
              0 => const _Alerts(),
              1 => _List(onChanged: _refresh),
              _ => const _Movements(),
            },
          ),
        ),
      ],
    ),
  );
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.direction, required this.onTap});
  final StockDirection direction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inbound = direction == StockDirection.giris;
    return Material(
      color: inbound ? EtkenColors.green : EtkenColors.coral,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner_rounded, size: 20, color: EtkenColors.ink),
              const SizedBox(width: 8),
              Text(
                inbound ? 'Karekodla giriş' : 'Karekodla çıkış',
                style: bodyStyle(14, weight: FontWeight.w700, color: EtkenColors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
    child: Semantics(header: true, child: Text(text, style: _section())),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.meta, this.leading, this.trailing, this.divider = true});
  final String title;
  final String meta;
  final Widget? leading;
  final Widget? trailing;
  final bool divider;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 56),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: divider
        ? const BoxDecoration(
            border: Border(top: BorderSide(color: EtkenColors.lineSoft)),
          )
        : null,
    child: Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: _title()),
              const SizedBox(height: 2),
              Text(meta, style: _meta()),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    ),
  );
}

class _Alerts extends ConsumerWidget {
  const _Alerts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(stockAlertsProvider);
    return a.when(
      loading: () => const Loading(),
      error: (e, _) => ListView(children: [ErrorPanel(e, onRetry: () => ref.invalidate(stockAlertsProvider))]),
      data: (a) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const _Section('SKT yaklaşanlar (90 gün)'),
          if (a.expiring.isEmpty)
            const EmptyPanel(
              title: 'Yaklaşan SKT yok',
              body: '90 gün içinde son kullanma tarihi dolan parti bulunmuyor.',
            )
          else
            EtkenCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, (item, batch, days)) in a.expiring.indexed)
                    _Row(
                      divider: i > 0,
                      title: item.drugName,
                      meta:
                          'Parti ${batch.lot ?? '-'} · ${batch.quantity} adet · SKT ${batch.expiry == null ? '-' : fmtDate(batch.expiry!)}',
                      leading: SizedBox(
                        width: 44,
                        child: Text(
                          days < 0 ? 'Geçti' : '$days\ngün',
                          textAlign: TextAlign.center,
                          style: bodyStyle(
                            13,
                            weight: FontWeight.w800,
                            height: 1.1,
                            color: days <= 30 ? EtkenColors.riskCritical : EtkenColors.ink,
                          ),
                        ),
                      ),
                      trailing: RiskBadge(
                        days <= 30
                            ? Severity.kritik
                            : days <= 60
                            ? Severity.onemli
                            : Severity.bilgi,
                        compact: true,
                      ),
                    ),
                ],
              ),
            ),
          const _Section('Kritik seviyede'),
          if (a.critical.isEmpty)
            const EmptyPanel(title: 'Kritik seviyede ürün yok', body: 'Kritik seviye, ürün eklerken tanımlanır.')
          else
            EtkenCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, it) in a.critical.indexed)
                    _Row(
                      divider: i > 0,
                      title: it.drugName,
                      meta: '${it.quantity} adet · kritik seviye ${it.criticalLevel}',
                      trailing: const RiskBadge(Severity.onemli, compact: true),
                    ),
                ],
              ),
            ),
          const _Section('Tükenenler ve eşdeğerleri'),
          if (a.outOfStock.isEmpty)
            const EmptyPanel(
              title: 'Tükenen ürün yok',
              body: 'Adedi sıfıra düşen ürünler burada stoktaki eşdeğerleriyle listelenir.',
            )
          else
            for (final (item, alts) in a.outOfStock) ...[
              EtkenCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.drugName, style: _title()),
                    const SizedBox(height: 4),
                    if (alts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('Listede eşdeğer ürün yok.', style: _meta()),
                      )
                    else
                      for (final (d, n) in alts.take(4))
                        InkWell(
                          onTap: () => context.push('/ilac/${d.id}'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    d.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: bodyStyle(14),
                                  ),
                                ),
                                Text(
                                  n > 0 ? 'Stokta $n' : 'Stokta yok',
                                  style: bodyStyle(
                                    13,
                                    weight: FontWeight.w700,
                                    color: n > 0 ? EtkenColors.commercial : EtkenColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.onChanged});
  final VoidCallback onChanged;

  Future<void> _editQty(BuildContext context, WidgetRef ref, StockBatch b) async {
    final r = await showDialog<(int, String?)>(
      context: context,
      builder: (_) => _QtyDialog(current: b.quantity),
    );
    if (r == null) return;
    try {
      await ref.read(stockRepositoryProvider).setQuantity(b.id, r.$1, note: r.$2);
      onChanged();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(stockListProvider);
    return l.when(
      loading: () => const Loading(),
      error: (e, _) => ListView(children: [ErrorPanel(e, onRetry: () => ref.invalidate(stockListProvider))]),
      data: (items) => items.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                EmptyPanel(
                  title: 'Stok kaydı yok',
                  body: 'Karekodla giriş yapın veya elle ürün ekleyin. Seri, parti ve SKT karekoddan otomatik alınır.',
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                for (final it in items) ...[
                  EtkenCard(
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(it.drugName, style: _title())),
                            Text(
                              '${it.quantity} adet',
                              style: bodyStyle(
                                14,
                                weight: FontWeight.w800,
                                color: it.isOut ? EtkenColors.riskCritical : EtkenColors.ink,
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Seçenekler',
                              onSelected: (_) async {
                                await ref.read(stockRepositoryProvider).deleteItem(it.id);
                                onChanged();
                              },
                              itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Stok kaydını sil'))],
                            ),
                          ],
                        ),
                        for (final b in it.batches.where((b) => b.quantity > 0 || b.serial == null))
                          InkWell(
                            onTap: () => _editQty(context, ref, b),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 6, 10, 6),
                              child: Row(
                                children: [
                                  const Icon(Icons.inventory_2_outlined, size: 16, color: EtkenColors.muted),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Parti ${b.lot ?? '-'}${b.serial == null ? '' : ' · seri ${b.serial}'} · SKT ${b.expiry == null ? 'bilinmiyor' : fmtDate(b.expiry!)}',
                                      style: _meta(),
                                    ),
                                  ),
                                  Text('${b.quantity}', style: bodyStyle(14, weight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _Movements extends ConsumerWidget {
  const _Movements();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(stockMovementsProvider);
    return m.when(
      loading: () => const Loading(),
      error: (e, _) => ListView(children: [ErrorPanel(e, onRetry: () => ref.invalidate(stockMovementsProvider))]),
      data: (items) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (items.isEmpty)
            const EmptyPanel(
              title: 'Hareket yok',
              body: 'Stok girişleri, çıkışları ve düzeltmeler kullanıcı ve saatiyle burada listelenir.',
            )
          else
            EtkenCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, x) in items.indexed)
                    _Row(
                      divider: i > 0,
                      title: x.drugName,
                      meta: [
                        fmtDateTime(x.at),
                        x.userName,
                        if (x.serial != null) 'seri ${x.serial}' else if (x.lot != null) 'parti ${x.lot}',
                        if (x.note != null && x.note!.isNotEmpty) x.note!,
                      ].join(' · '),
                      leading: Icon(
                        switch (x.direction) {
                          'giris' => Icons.add_circle_rounded,
                          'cikis' => Icons.remove_circle_rounded,
                          _ => Icons.tune_rounded,
                        },
                        size: 22,
                        color: switch (x.direction) {
                          'giris' => EtkenColors.commercial,
                          'cikis' => EtkenColors.riskCritical,
                          _ => EtkenColors.muted,
                        },
                      ),
                      trailing: Text(
                        '${x.label} ${x.quantity > 0 && x.direction == 'duzeltme' ? '+' : ''}${x.quantity}',
                        style: bodyStyle(13, weight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _QtyDialog extends StatefulWidget {
  const _QtyDialog({required this.current});
  final int current;
  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  late final _q = TextEditingController(text: '${widget.current}');
  final _note = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Adet düzeltme'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _q,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Yeni adet'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: 'Gerekçe (örn. kırık, sayım)'),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(
        onPressed: () {
          final v = int.tryParse(_q.text);
          if (v != null) Navigator.pop(context, (v, _note.text.trim().isEmpty ? null : _note.text.trim()));
        },
        child: const Text('Kaydet'),
      ),
    ],
  );
}

class _BatchInput {
  _BatchInput(this.critical, this.quantity, this.lot, this.expiry);
  final int critical;
  final int quantity;
  final String? lot;
  final DateTime? expiry;
}

class _BatchDialog extends StatefulWidget {
  const _BatchDialog({required this.drug});
  final Drug drug;
  @override
  State<_BatchDialog> createState() => _BatchDialogState();
}

class _BatchDialogState extends State<_BatchDialog> {
  final _qty = TextEditingController(text: '1');
  final _crit = TextEditingController(text: '0');
  final _lot = TextEditingController();
  DateTime? _exp;

  @override
  void dispose() {
    for (final c in [_qty, _crit, _lot]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.drug.name, style: bodyStyle(17, weight: FontWeight.w700)),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Adet'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _crit,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Kritik seviye'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lot,
            decoration: const InputDecoration(labelText: 'Parti no (isteğe bağlı)'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                initialDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setState(() => _exp = d);
            },
            icon: const Icon(Icons.event_outlined),
            label: Text(_exp == null ? 'Son kullanma tarihi' : 'SKT ${fmtDate(_exp!)}'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _BatchInput(
            int.tryParse(_crit.text) ?? 0,
            int.tryParse(_qty.text) ?? 0,
            _lot.text.trim().isEmpty ? null : _lot.text.trim(),
            _exp,
          ),
        ),
        child: const Text('Ekle'),
      ),
    ],
  );
}
