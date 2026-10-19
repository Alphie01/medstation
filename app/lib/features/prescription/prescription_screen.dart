import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/glyphs.dart';
import '../search/drug_picker.dart';
import 'prescription_draft.dart';

class PrescriptionScreen extends ConsumerStatefulWidget {
  const PrescriptionScreen({super.key});
  @override
  ConsumerState<PrescriptionScreen> createState() => _PrescriptionScreenState();
}

class _PrescriptionScreenState extends ConsumerState<PrescriptionScreen> {
  bool _checking = false;

  PrescriptionDraftNotifier get _draft => ref.read(prescriptionDraftProvider.notifier);

  Future<void> _addManual([String? initial]) async {
    final d = await pickDrug(context, initial: initial);
    if (d != null) _draft.addDrug(d);
  }

  Future<void> _medula() async {
    final code = await showDialog<String>(context: context, builder: (_) => const _CodeDialog());
    if (code == null || !mounted) return;
    try {
      final lines = await ref.read(prescriptionRepositoryProvider).fromMedula(code);
      for (final l in lines) {
        _draft.addDrug(l.drug);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(e.code == 'integration_not_authorized' ? 'MEDULA bağlı değil' : 'e-Reçete alınamadı'),
          content: Text(e.message),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
        ),
      );
    }
  }

  /// On-device OCR: the photo never leaves the phone. Recognised lines are
  /// only suggestions; the pharmacist picks and confirms each product.
  Future<void> _photo() async {
    final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
    if (img == null || !mounted) return;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    List<String> lines;
    try {
      final r = await recognizer.processImage(InputImage.fromFilePath(img.path));
      lines = [
        for (final b in r.blocks)
          for (final l in b.lines)
            if (RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]{3,}').hasMatch(l.text) && l.text.trim().length >= 4) l.text.trim(),
      ];
    } finally {
      await recognizer.close();
    }
    if (!mounted) return;
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fotoğrafta okunabilir metin bulunamadı.')));
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _OcrLines(lines: lines),
    );
    if (picked != null) await _addManual(picked);
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final r = await ref.read(prescriptionRepositoryProvider).check(ref.read(prescriptionDraftProvider));
      ref.read(lastCheckProvider.notifier).set(r);
      if (mounted) context.push('/recete/sonuc');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(prescriptionDraftProvider);
    return Scaffold(
      body: Stack(children: [
        ListView(padding: EdgeInsets.only(bottom: draft.lines.isEmpty ? 28 : 110), children: [
          HeroHeader(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Semantics(header: true, child: Text('Reçete kontrolü', style: displayStyle(32, weight: FontWeight.w800, color: Colors.white)))),
                if (draft.lines.isNotEmpty)
                  HeaderIconButton(icon: Icons.delete_sweep_outlined, label: 'Reçeteyi temizle', onPressed: _draft.clear),
              ]),
              const SizedBox(height: 8),
              Text('İlaçları ekleyin; etkileşim, mükerrer madde ve doz kontrolleri doğrulanmış verilerle yapılır.',
                  style: bodyStyle(15, color: Colors.white.withValues(alpha: 0.82))),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: _InputTile(icon: Icons.search_rounded, label: 'İlaç ara', onTap: _addManual)),
                const SizedBox(width: 8),
                Expanded(child: _InputTile(icon: Icons.qr_code_scanner_rounded, label: 'Karekod', onTap: () => context.push('/tara?hedef=recete'))),
                const SizedBox(width: 8),
                Expanded(child: _InputTile(icon: Icons.photo_camera_outlined, label: 'Fotoğraf', onTap: _photo)),
                const SizedBox(width: 8),
                Expanded(child: _InputTile(icon: Icons.receipt_long_outlined, label: 'e-Reçete', onTap: _medula)),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (draft.lines.isEmpty)
                const EmptyPanel(title: 'Reçete boş', body: 'Yukarıdan ilaç arayın, karekod okutun veya reçete fotoğrafı çekin.')
              else
                for (final l in draft.lines) ...[
                  _LineCard(line: l, onRemove: () => _draft.remove(l.id), onPosology: (p) => _draft.setPosology(l.id, p)),
                  const SizedBox(height: 10),
                ],
              const SectionTitle('Hasta bilgisi'),
              _PatientCard(draft: draft, notifier: _draft),
            ]),
          ),
        ]),
        if (draft.lines.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: CtaButton(label: 'Reçeteyi kontrol et', badge: '${draft.lines.length}', loading: _checking, onPressed: _check),
          ),
      ]),
    );
  }
}

class _InputTile extends StatelessWidget {
  const _InputTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center, style: bodyStyle(13, weight: FontWeight.w600, color: Colors.white)),
            ]),
          ),
        ),
      );
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line, required this.onRemove, required this.onPosology});
  final DraftLine line;
  final VoidCallback onRemove;
  final ValueChanged<Posology> onPosology;

  @override
  Widget build(BuildContext context) {
    final d = line.drug;
    final p = line.posology;
    final liquid = d.formGroup == FormGroup.sivi;
    return EtkenCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(width: 44, height: 44, child: Center(child: PillGlyph.forDrug(d, size: 36))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text([d.name, d.strength].whereType<String>().join(' '), style: bodyStyle(17, weight: FontWeight.w700, height: 1.2)),
              Text(d.ingredients.isEmpty ? 'Etken madde bilgisi yok' : d.ingredients.map((i) => i.name).join(' + '),
                  style: bodyStyle(14, color: EtkenColors.muted)),
            ]),
          ),
          IconButton(onPressed: onRemove, tooltip: 'Kalemi çıkar', icon: const Icon(Icons.close_rounded)),
        ]),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(children: [
            Expanded(
              child: _NumField(
                label: 'Günde',
                suffix: 'kez',
                value: p.timesPerDay?.toDouble(),
                integer: true,
                onChanged: (v) => onPosology(Posology(timesPerDay: v?.round(), unitsPerDose: p.unitsPerDose, days: p.days)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _NumField(
                label: 'Her seferde',
                suffix: liquid ? 'ml' : 'adet',
                value: p.unitsPerDose,
                onChanged: (v) => onPosology(Posology(timesPerDay: p.timesPerDay, unitsPerDose: v, days: p.days)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _NumField extends StatefulWidget {
  const _NumField({required this.label, required this.value, required this.onChanged, this.integer = false, this.suffix});
  final String label;
  final String? suffix;
  final double? value;
  final ValueChanged<double?> onChanged;
  final bool integer;
  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final _c = TextEditingController(text: _fmt(widget.value));

  static String _fmt(double? v) =>
      v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString().replaceAll('.', ','));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        keyboardType: TextInputType.numberWithOptions(decimal: !widget.integer),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(widget.integer ? r'\d' : r'[\d.,]'))],
        decoration: InputDecoration(labelText: widget.label, suffixText: widget.suffix, isDense: true),
        onChanged: (s) {
          final v = double.tryParse(s.replaceAll(',', '.'));
          widget.onChanged(v != null && v > 0 ? v : null);
        },
      );
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.draft, required this.notifier});
  final PrescriptionDraft draft;
  final PrescriptionDraftNotifier notifier;

  @override
  Widget build(BuildContext context) => EtkenCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: _NumField(label: 'Yaş', suffix: 'yıl', value: draft.ageYears, onChanged: notifier.setAge)),
            const SizedBox(width: 10),
            Expanded(child: _NumField(label: 'Kilo', suffix: 'kg', value: draft.weightKg, onChanged: notifier.setWeight)),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<RxType>(
            initialValue: draft.rxType ?? RxType.bilinmiyor,
            style: bodyStyle(16, color: EtkenColors.ink),
            decoration: const InputDecoration(labelText: 'Reçete türü', isDense: true),
            items: [
              const DropdownMenuItem(value: RxType.bilinmiyor, child: Text('Belirtilmedi')),
              for (final t in RxType.values.where((t) => t != RxType.bilinmiyor && t != RxType.receteSiz))
                DropdownMenuItem(value: t, child: Text(t.label)),
            ],
            // "Belirtilmedi" is sent as no type, so the rule engine asks to check it.
            onChanged: (t) => notifier.setRxType(t == RxType.bilinmiyor ? null : t),
          ),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lock_outline_rounded, size: 18, color: EtkenColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Hasta adı veya T.C. kimlik no girilmez. Kontrol kaydında yalnızca ilaçlar, yaş ve kilo saklanır (KVKK).',
                  style: bodyStyle(13, color: EtkenColors.muted)),
            ),
          ]),
        ]),
      );
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog();
  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('e-Reçete kodu'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _c,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'örn. 1A2B3C4'),
          ),
          const SizedBox(height: 10),
          Text('İçerik yalnızca yetkili MEDULA entegrasyonu üzerinden alınır.', style: bodyStyle(13, color: EtkenColors.muted)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, _c.text.trim()), child: const Text('Getir')),
        ],
      );
}

class _OcrLines extends StatelessWidget {
  const _OcrLines({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Okunan satırlar', style: displayStyle(22, color: EtkenColors.ink)),
          const SizedBox(height: 6),
          Text('Bir satıra dokunun; ürünü listeden siz seçip onaylarsınız. Okuma hatalı olabilir.',
              style: bodyStyle(14, color: EtkenColors.muted)),
          const SizedBox(height: 12),
          for (final l in lines)
            ListTile(
              title: Text(l),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, l),
            ),
        ]),
      );
}
