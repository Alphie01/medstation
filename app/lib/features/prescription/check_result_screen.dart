import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../search/results_screen.dart';
import 'prescription_draft.dart';

class CheckResultScreen extends ConsumerStatefulWidget {
  const CheckResultScreen({super.key});
  @override
  ConsumerState<CheckResultScreen> createState() => _CheckResultScreenState();
}

class _CheckResultScreenState extends ConsumerState<CheckResultScreen> {
  final _decisions = <String, String>{};

  Future<void> _decide(CheckResult r, CheckFinding f, String decision) async {
    String? note;
    if (decision == 'not' || decision == 'reddedildi') {
      note = await showDialog<String>(context: context, builder: (_) => _NoteDialog(reject: decision == 'reddedildi'));
      if (note == null) return;
    }
    final prev = _decisions[f.id];
    setState(() => _decisions[f.id] = decision);
    try {
      await ref.read(prescriptionRepositoryProvider).decide(r.checkId, f.id, decision, note: note);
    } catch (e) {
      if (!mounted) return;
      setState(() => prev == null ? _decisions.remove(f.id) : _decisions[f.id] = prev);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Karar kaydedilemedi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(lastCheckProvider);
    if (r == null) {
      return Scaffold(appBar: AppBar(), body: const Padding(padding: EdgeInsets.all(16), child: EmptyPanel(title: 'Kontrol yok', body: 'Önce bir reçete kontrol edin.')));
    }
    final open = r.findings.where((f) => !_decisions.containsKey(f.id)).length;
    final altLines = r.lines.where((l) => (r.alternatives[l.id] ?? const []).isNotEmpty).toList();

    return Scaffold(
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        HeroHeader(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              HeaderIconButton(icon: Icons.arrow_back_ios_new_rounded, label: 'Reçeteye dön', onPressed: () => context.pop()),
              const SizedBox(width: 12),
              Expanded(child: Semantics(header: true, child: Text('Kontrol listesi', style: displayStyle(26, weight: FontWeight.w800, color: Colors.white)))),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              for (final s in Severity.values) ...[
                Expanded(child: _CountTile(severity: s, count: r.count(s))),
                if (s != Severity.values.last) const SizedBox(width: 6),
              ],
            ]),
            const SizedBox(height: 12),
            Text('${r.lines.length} kalem · ${fmtDateTime(r.checkedAt)} · $open madde eczacı değerlendirmesi bekliyor',
                style: bodyStyle(14, color: Colors.white.withValues(alpha: 0.8))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (r.anySample) ...[const SampleBanner(), const SizedBox(height: 12)],
            _KnowledgeCard(r: r),
            const SizedBox(height: 12),
            if (r.findings.isEmpty)
              const EmptyPanel(
                title: 'Kural motoru bir sorun bulmadı',
                body: 'Bu, yalnızca bağlı veri kaynaklarına göre bir sonuçtur. Reçeteyi her zaman kendi değerlendirmenizle onaylayın.',
              )
            else
              for (final f in r.findings) ...[
                _FindingCard(
                  f: f,
                  lineNames: f.lineIds.map(r.lineName).toList(),
                  decision: _decisions[f.id],
                  onDecide: (d) => _decide(r, f, d),
                  onAsk: () {
                    final line = r.lines.where((l) => f.lineIds.contains(l.id)).firstOrNull;
                    final q = '${f.title}. Bu konuda KÜB/KT ne söylüyor, eczacı neyi kontrol etmeli?';
                    context.go(Uri(path: '/asistan', queryParameters: {
                      'q': q,
                      if (line != null) 'drug': line.drug.id,
                      if (line != null) 'name': line.drug.name,
                    }).toString());
                  },
                ),
                const SizedBox(height: 10),
              ],
            const SectionTitle('Klinik alternatifler'),
            Text('Aynı etken madde, miktar ve formdaki eşdeğer ürünler. Değişim kararı eczacıya aittir.',
                style: bodyStyle(14, color: EtkenColors.muted)),
            const SizedBox(height: 10),
            if (altLines.isEmpty)
              const EmptyPanel(title: 'Eşdeğer bulunamadı', body: 'Reçetedeki ürünler için listede eşdeğer ürün yok.')
            else
              for (final l in altLines) ...[
                EtkenCard(
                  padding: EdgeInsets.zero,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Text('${r.lineName(l.id)} yerine', style: bodyStyle(15, weight: FontWeight.w700, color: EtkenColors.muted)),
                    ),
                    for (final d in r.alternatives[l.id]!.take(5)) DrugRow(drug: d),
                  ]),
                ),
                const SizedBox(height: 10),
              ],
            const SectionTitle('Destekleyici ürünler'),
            EtkenCard(
              color: EtkenColors.commercialTint,
              border: Border.all(color: EtkenColors.commercial.withValues(alpha: 0.4)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: EtkenColors.commercial, borderRadius: BorderRadius.circular(999)),
                  child: Text('TİCARİ · KLİNİK ÖNERİ DEĞİLDİR', style: bodyStyle(12, weight: FontWeight.w800, color: Colors.white)),
                ),
                const SizedBox(height: 10),
                if (!r.commercialConnected)
                  Text('Eczanenizin destekleyici ürün kataloğu boş. Daha fazla › Destekleyici ürünler bölümünden, hangi etken madde veya ATC grubunda önerileceğini belirterek ürün ekleyebilirsiniz.',
                      style: bodyStyle(15))
                else if (r.commercialItems.isEmpty)
                  Text('Bu reçete için katalogdaki ürünlerden eşleşen yok.', style: bodyStyle(15))
                else
                  for (final x in r.commercialItems)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x['name'] as String, style: bodyStyle(15, weight: FontWeight.w700)),
                        Text([
                          'Eşleşme: ${x['because']}',
                          if ((x['note'] as String?)?.isNotEmpty == true) x['note'] as String,
                        ].join(' · '), style: bodyStyle(13, color: EtkenColors.muted)),
                      ]),
                    ),
                const SizedBox(height: 6),
                Text('Eczanenizin kendi kataloğundan; klinik bulguları etkilemez.', style: bodyStyle(12, color: EtkenColors.muted)),
              ]),
            ),
            const SizedBox(height: 18),
            Text('Bu liste karar desteğidir; otomatik karar vermez. Son klinik değerlendirme ve onay eczacıya aittir.',
                style: bodyStyle(13, color: EtkenColors.muted)),
          ]),
        ),
      ]),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.severity, required this.count});
  final Severity severity;
  final int count;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, icon) = RiskBadge.style(severity);
    return Semantics(
      label: '${severity.label}: $count',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(color: count == 0 ? Colors.white.withValues(alpha: 0.1) : bg, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Icon(icon, size: 18, color: count == 0 ? Colors.white70 : fg),
          Text('$count', style: displayStyle(22, weight: FontWeight.w800, color: count == 0 ? Colors.white : fg)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(severity.label, maxLines: 1,
                style: bodyStyle(11, weight: FontWeight.w600, color: count == 0 ? Colors.white70 : fg)),
          ),
        ]),
      ),
    );
  }
}

class _KnowledgeCard extends StatelessWidget {
  const _KnowledgeCard({required this.r});
  final CheckResult r;

  @override
  Widget build(BuildContext context) => EtkenCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Kontrolde kullanılan veriler', style: bodyStyle(14, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          ProvenanceLine(r.lines.first.drug.provenance, prefix: 'İlaç listesi'),
          ProvenanceLine(r.interactionDb, prefix: 'Etkileşim veritabanı'),
        ]),
      );
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.f, required this.lineNames, required this.decision, required this.onDecide, required this.onAsk});
  final CheckFinding f;
  final List<String> lineNames;
  final String? decision;
  final ValueChanged<String> onDecide;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final (fg, _, _) = RiskBadge.style(f.severity);
    return Container(
      decoration: BoxDecoration(
        color: EtkenColors.surface,
        borderRadius: BorderRadius.circular(EtkenRadius.card),
        border: Border.all(color: f.severity == Severity.kritik ? fg : EtkenColors.line, width: f.severity == Severity.kritik ? 2 : 1),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          RiskBadge(f.severity),
          const SizedBox(width: 8),
          Expanded(child: Text(f.type.label, maxLines: 2, style: bodyStyle(13, weight: FontWeight.w600, color: EtkenColors.muted))),
          if (!f.verified)
            Tooltip(
              message: 'Veri eksik veya doğrulanamadı',
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.report_gmailerrorred_outlined, size: 16, color: EtkenColors.muted),
                const SizedBox(width: 3),
                Text('doğrulanmadı', style: bodyStyle(12, color: EtkenColors.muted)),
              ]),
            ),
        ]),
        const SizedBox(height: 10),
        Text(f.title, style: bodyStyle(17, weight: FontWeight.w700, height: 1.25)),
        const SizedBox(height: 4),
        Text(f.detail, style: bodyStyle(15, color: EtkenColors.ink)),
        if (lineNames.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('İlgili: ${lineNames.toSet().join(', ')}', style: bodyStyle(13, color: EtkenColors.muted)),
        ],
        if (f.source != null) ...[
          const SizedBox(height: 4),
          Text('Kaynak: ${f.source!.source}${f.source!.section == null ? '' : ', ${f.source!.section}'}',
              style: bodyStyle(13, color: EtkenColors.muted)),
        ],
        const SizedBox(height: 10),
        if (decision != null)
          Row(children: [
            Icon(
              decision == 'onaylandi' ? Icons.check_circle_rounded : decision == 'reddedildi' ? Icons.cancel_rounded : Icons.sticky_note_2_outlined,
              color: EtkenColors.navy,
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(switch (decision) { 'onaylandi' => 'Değerlendirildi, onaylandı', 'reddedildi' => 'Reddedildi', _ => 'Not eklendi' },
                style: bodyStyle(14, weight: FontWeight.w700, color: EtkenColors.navy)),
            const Spacer(),
            TextButton(onPressed: () => onDecide('not'), child: const Text('Not')),
          ])
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: () => onDecide('onaylandi'),
              child: const Text('Değerlendirdim'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: () => onDecide('reddedildi'),
              child: const Text('İlaç verilmeyecek'),
            ),
            TextButton(style: TextButton.styleFrom(minimumSize: const Size(44, 44)), onPressed: () => onDecide('not'), child: const Text('Not ekle')),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: onAsk,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('Asistana sor'),
            ),
          ]),
      ]),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.reject});
  final bool reject;
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.reject ? 'Gerekçe' : 'Not'),
        content: TextField(
          controller: _c,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Hasta kimlik bilgisi yazmayın'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, _c.text.trim()), child: const Text('Kaydet')),
        ],
      );
}
