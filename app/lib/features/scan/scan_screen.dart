import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/glyphs.dart';
import '../prescription/prescription_draft.dart';
import '../stock/stock_repository.dart';

enum ScanTarget { detail, prescription, stock }

class LastScanned extends Notifier<Drug?> {
  @override
  Drug? build() => null;
  void set(Drug d) => state = d;
}

final lastScannedProvider = NotifierProvider<LastScanned, Drug?>(LastScanned.new);

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, this.target = ScanTarget.detail, this.direction = StockDirection.giris});
  final ScanTarget target;

  /// Initial stock direction; can be switched on the screen.
  final StockDirection direction;
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _ctrl = MobileScannerController(
    formats: const [BarcodeFormat.dataMatrix, BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.code128],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _busy = false;
  String? _message;
  late StockDirection _dir = widget.direction;
  final _session = <ScanMovement>[];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null || _busy) return;
    setState(() => (_busy = true, _message = null));
    await _ctrl.stop();
    try {
      await _handle(raw);
    } on ApiException catch (e) {
      setState(() => _message = e.message);
      await _ctrl.start();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handle(String raw) async {
    final api = ref.read(apiProvider);
    if (widget.target == ScanTarget.stock) {
      final r = await api.post('/drugs/scan', {'raw': raw});
      if (!await _confirmAmbiguous(r['code'] as Map<String, dynamic>)) return _ctrl.start();
      final m = await ref.read(stockRepositoryProvider).scan(raw, _dir);
      ref.invalidate(stockListProvider);
      ref.invalidate(stockAlertsProvider);
      ref.invalidate(stockMovementsProvider);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _session.insert(0, m);
        _message = null;
      });
      // Wait briefly so the same pack is not read twice.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await _ctrl.start();
      return;
    }
    final r = await api.post('/drugs/scan', {'raw': raw});
    final code = r['code'] as Map<String, dynamic>;
    if (r['drug'] == null) {
      setState(() => _message = 'Bu barkod (${code['barcode']}) ilaç listesinde yok.');
      await _ctrl.start();
      return;
    }
    if (!await _confirmAmbiguous(code)) return _ctrl.start();
    final drug = Drug.fromJson(r['drug'] as Map<String, dynamic>);
    ref.read(lastScannedProvider.notifier).set(drug);
    if (!mounted) return;
    if (widget.target == ScanTarget.prescription) {
      ref.read(prescriptionDraftProvider.notifier).addDrug(drug);
      context.pop();
    } else {
      context.pushReplacement('/ilac/${drug.id}');
    }
  }

  Future<bool> _confirmAmbiguous(Map<String, dynamic> code) async {
    if (code['ambiguous'] != true) return true;
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Karekodu doğrulayın'),
            content: Text('Ayraç olmadan okundu; alanlar tahmini ayrıldı.\n\n'
                'Seri: ${code['serial'] ?? '-'}\nSKT: ${code['expiry'] ?? '-'}\nParti: ${code['lot'] ?? '-'}\n\n'
                'Kutudaki bilgilerle aynı mı?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hayır, tekrar okut')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Evet')),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final last = ref.watch(lastScannedProvider);
    final title = switch (widget.target) {
      ScanTarget.stock => 'Stok: karekod okut',
      ScanTarget.prescription => 'Reçeteye karekod okut',
      ScanTarget.detail => 'Karekod okut',
    };
    return Scaffold(
      backgroundColor: EtkenColors.navy,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              Expanded(child: Semantics(header: true, child: Text(title, style: displayStyle(20, color: Colors.white)))),
              HeaderIconButton(icon: Icons.flash_on_rounded, label: 'Fener', onPressed: _ctrl.toggleTorch),
              const SizedBox(width: 8),
              HeaderIconButton(icon: Icons.close_rounded, label: 'Kapat', onPressed: () => context.pop()),
            ]),
          ),
          if (widget.target == ScanTarget.stock)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(18)),
                child: Row(children: [
                  for (final d in StockDirection.values)
                    Expanded(
                      child: Semantics(
                        selected: _dir == d,
                        button: true,
                        child: Material(
                          color: _dir == d ? (d == StockDirection.giris ? EtkenColors.green : EtkenColors.coral) : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setState(() => _dir = d),
                            child: SizedBox(
                              height: 46,
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(d == StockDirection.giris ? Icons.add_box_outlined : Icons.indeterminate_check_box_outlined,
                                    size: 20, color: _dir == d ? EtkenColors.ink : Colors.white),
                                const SizedBox(width: 6),
                                Text(d == StockDirection.giris ? 'Giriş (stoğa al)' : 'Çıkış (stoktan düş)',
                                    style: bodyStyle(14, weight: FontWeight.w700, color: _dir == d ? EtkenColors.ink : Colors.white)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox.square(
                dimension: 250,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(34),
                  child: Stack(fit: StackFit.expand, children: [
                    MobileScanner(
                      controller: _ctrl,
                      onDetect: _onDetect,
                      errorBuilder: (_, e) => ColoredBox(
                        color: Colors.white.withValues(alpha: 0.05),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              e.errorCode == MobileScannerErrorCode.permissionDenied
                                  ? 'Kamera izni verilmedi. Ayarlardan izin verin.'
                                  : 'Kamera açılamadı.',
                              textAlign: TextAlign.center,
                              style: bodyStyle(15, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const CustomPaint(painter: _FramePainter()),
                    if (_busy) const ColoredBox(color: Colors.black38, child: Loading()),
                  ]),
                ),
              ),
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  _message ??
                      (widget.target == ScanTarget.stock
                          ? (_dir == StockDirection.giris
                              ? 'Karekodu okutun; seri, parti ve SKT ile stoğa girer.'
                              : 'Karekodu okutun; o seri numaralı kutu stoktan düşer.')
                          : 'Kutudaki karekodu çerçeveye getirin.'),
                  textAlign: TextAlign.center,
                  style: bodyStyle(18, color: _message == null ? Colors.white.withValues(alpha: 0.88) : EtkenColors.amber, height: 1.35),
                ),
              ),
            ]),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 20 + MediaQuery.paddingOf(context).bottom),
            decoration: const BoxDecoration(color: EtkenColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.target == ScanTarget.stock && _session.isNotEmpty) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                    for (final m in _session)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          Icon(m.direction == StockDirection.giris ? Icons.add_circle_rounded : Icons.remove_circle_rounded,
                              size: 20, color: m.direction == StockDirection.giris ? EtkenColors.commercial : EtkenColors.riskCritical),
                          const SizedBox(width: 8),
                          Expanded(child: Text(m.item.drugName, maxLines: 1, overflow: TextOverflow.ellipsis, style: bodyStyle(14, weight: FontWeight.w600))),
                          Text('stok ${m.item.quantity}', style: bodyStyle(13, color: EtkenColors.muted)),
                        ]),
                      ),
                  ]),
                ),
                Text('Bu oturumda ${_session.where((m) => m.direction == StockDirection.giris).length} giriş, '
                    '${_session.where((m) => m.direction == StockDirection.cikis).length} çıkış',
                    style: bodyStyle(13, color: EtkenColors.muted)),
                const SizedBox(height: 10),
              ],
              if (last != null && widget.target == ScanTarget.detail) ...[
                EtkenCard(
                  color: EtkenColors.bg,
                  radius: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  onTap: () => context.pushReplacement('/ilac/${last.id}'),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: EtkenColors.surface, borderRadius: BorderRadius.circular(14)),
                      child: PillGlyph.forDrug(last, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Son okutulan', style: bodyStyle(13, color: EtkenColors.muted)),
                        Text([last.name, last.strength].whereType<String>().join(' '), style: bodyStyle(17, weight: FontWeight.w700)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: EtkenColors.muted),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(44, 58)),
                  onPressed: () => context.pop(),
                  child: Text(widget.target == ScanTarget.detail ? 'Etken maddeyi elle yaz' : 'Bitti'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter();
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = EtkenColors.coral
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    const l = 56.0, o = 3.0;
    void corner(Offset a, Offset b, Offset c) {
      canvas.drawPath(Path()..moveTo(a.dx, a.dy)..quadraticBezierTo(b.dx, b.dy, c.dx, c.dy), p);
    }

    corner(Offset(o, l), Offset(o, o), Offset(l, o));
    corner(Offset(s.width - l, o), Offset(s.width - o, o), Offset(s.width - o, l));
    corner(Offset(o, s.height - l), Offset(o, s.height - o), Offset(l, s.height - o));
    corner(Offset(s.width - l, s.height - o), Offset(s.width - o, s.height - o), Offset(s.width - o, s.height - l));
    final y = s.height / 2;
    canvas.drawLine(Offset(28, y), Offset(s.width - 28, y), Paint()
      ..color = EtkenColors.coral
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 6));
  }

  @override
  bool shouldRepaint(_FramePainter old) => false;
}
