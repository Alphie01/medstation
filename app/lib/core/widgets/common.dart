import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../network/api_client.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'glyphs.dart';

final _date = DateFormat('d MMMM y', 'tr_TR');
final _dateTime = DateFormat('d MMM y HH:mm', 'tr_TR');
String fmtDate(DateTime d) => _date.format(d.toLocal());
String fmtDateTime(DateTime d) => _dateTime.format(d.toLocal());
String fmtPrice(double? v) => v == null ? 'Veri yok' : '${NumberFormat.decimalPatternDigits(locale: 'tr_TR', decimalDigits: 2).format(v)} TL';

/// Navy header with rounded bottom corners, as in the reference.
class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 26), this.decor = false});
  final Widget child;
  final EdgeInsets padding;
  final bool decor;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: EtkenColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(EtkenRadius.hero)),
      ),
      child: Stack(children: [
        // Decor sits below the status bar, like the content.
        if (decor) ...[
          Positioned(right: -34, top: top + 52, child: const PillGlyph(a: EtkenColors.coral, b: EtkenColors.blue, size: 150, shadow: false)),
          Positioned(right: 128, top: top + 96, child: const _Dot()),
          Positioned(right: 14, top: top + 150, child: const PillGlyph(a: EtkenColors.green, b: EtkenColors.lavender, size: 90, shadow: false)),
        ],
        Padding(
          padding: padding.copyWith(top: padding.top + top),
          child: DefaultTextStyle(style: bodyStyle(16, color: Colors.white), child: child),
        ),
      ]),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(color: EtkenColors.amber, shape: BoxShape.circle),
      );
}

/// Translucent square icon button used on navy surfaces.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({super.key, required this.icon, required this.label, required this.onPressed, this.size = 44});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(EtkenRadius.button),
          child: InkWell(
            borderRadius: BorderRadius.circular(EtkenRadius.button),
            onTap: onPressed,
            child: SizedBox.square(dimension: size, child: Icon(icon, color: Colors.white, size: 22)),
          ),
        ),
      );
}

class EtkenCard extends StatelessWidget {
  const EtkenCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color = EtkenColors.surface, this.radius = EtkenRadius.card, this.onTap, this.border});
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final double radius;
  final VoidCallback? onTap;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), border: border),
      child: onTap == null ? content : Material(type: MaterialType.transparency, child: InkWell(onTap: onTap, child: content)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(4, 26, 4, 12), this.trailing});
  final String text;
  final EdgeInsets padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Semantics(header: true, child: Text(text, style: displayStyle(21, color: EtkenColors.ink)))),
          ?trailing,
        ]),
      );
}

/// Large bottom call-to-action (62px, 22px radius) with optional count badge.
class CtaButton extends StatelessWidget {
  const CtaButton({super.key, required this.label, required this.onPressed, this.badge, this.coral = false, this.loading = false});
  final String label;
  final VoidCallback? onPressed;
  final String? badge;
  final bool coral;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bg = coral ? EtkenColors.coral : EtkenColors.navy;
    final fg = coral ? EtkenColors.ink : Colors.white;
    return Semantics(
      button: true,
      child: Material(
        color: onPressed == null ? EtkenColors.placeholder : bg,
        borderRadius: BorderRadius.circular(EtkenRadius.cta),
        elevation: 0,
        shadowColor: bg,
        child: InkWell(
          borderRadius: BorderRadius.circular(EtkenRadius.cta),
          onTap: loading ? null : onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            padding: EdgeInsets.fromLTRB(22, 8, badge == null ? 22 : 10, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(EtkenRadius.cta),
              boxShadow: [BoxShadow(color: bg.withValues(alpha: 0.32), blurRadius: 32, offset: const Offset(0, 16))],
            ),
            child: Row(
              mainAxisAlignment: badge == null ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
              children: [
                if (loading)
                  SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
                else
                  Flexible(child: Text(label, style: bodyStyle(18, weight: FontWeight.w700, color: fg))),
                if (badge != null)
                  Container(
                    constraints: const BoxConstraints(minWidth: 44),
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: EtkenColors.coral, borderRadius: BorderRadius.circular(14)),
                    child: Text(badge!, style: displayStyle(19, weight: FontWeight.w800, color: EtkenColors.ink)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Risk level badge: colour + icon + label, never colour alone.
class RiskBadge extends StatelessWidget {
  const RiskBadge(this.severity, {super.key, this.compact = false});
  final Severity severity;
  final bool compact;

  static (Color, Color, IconData) style(Severity s) => switch (s) {
        Severity.kritik => (EtkenColors.riskCritical, EtkenColors.riskCriticalTint, Icons.error_rounded),
        Severity.onemli => (EtkenColors.riskMajor, EtkenColors.riskMajorTint, Icons.warning_amber_rounded),
        Severity.bilgi => (EtkenColors.riskInfo, EtkenColors.riskInfoTint, Icons.info_outline_rounded),
        Severity.dogrulanamadi => (EtkenColors.riskUnknown, EtkenColors.riskUnknownTint, Icons.help_outline_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg, icon) = style(severity);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: severity == Severity.dogrulanamadi ? Border.all(color: fg.withValues(alpha: 0.5)) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: compact ? 14 : 16, color: fg),
        const SizedBox(width: 5),
        Text(severity.label, style: bodyStyle(compact ? 12 : 13, weight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

/// "Kaynak · sürüm · son güncelleme" line required on every data surface.
class ProvenanceLine extends StatelessWidget {
  const ProvenanceLine(this.p, {super.key, this.prefix = 'Kaynak', this.light = false});
  final DataProvenance? p;
  final String prefix;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final color = light ? Colors.white.withValues(alpha: 0.75) : EtkenColors.muted;
    final text = p == null
        ? '$prefix: bağlı değil'
        : '$prefix: ${p!.source}${p!.version.isEmpty ? '' : ', ${p!.version} sürümü'} · son güncelleme ${fmtDate(p!.fetchedAt)}';
    return Text(text, style: bodyStyle(13, color: color));
  }
}

/// Shown whenever any displayed record comes from development sample data.
class SampleBanner extends StatelessWidget {
  const SampleBanner({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: EtkenColors.amber, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.science_outlined, size: 18, color: EtkenColors.ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text('ÖRNEK VERİ — gerçek ürün bilgisi değildir, klinik kararda kullanmayın.',
                  style: bodyStyle(13, weight: FontWeight.w700, color: EtkenColors.ink)),
            ),
          ]),
        ),
      );
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: EtkenColors.coral)));
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel(this.error, {super.key, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = error is ApiException ? (error as ApiException).message : 'Beklenmeyen bir hata oluştu';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: EtkenCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Yüklenemedi', style: displayStyle(20, color: EtkenColors.ink)),
          const SizedBox(height: 6),
          Text(msg, style: bodyStyle(15, color: EtkenColors.muted)),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ],
        ]),
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => EtkenCard(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: displayStyle(22, color: EtkenColors.ink)),
          const SizedBox(height: 6),
          Text(body, style: bodyStyle(15, color: EtkenColors.muted)),
        ]),
      );
}

/// Pill-shaped filter toggle (Tümü / Tablet / Sıvı).
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, required this.selected, required this.onTap, this.count});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? EtkenColors.ink : EtkenColors.surface,
          shape: StadiumBorder(side: selected ? BorderSide.none : const BorderSide(color: EtkenColors.lineStrong, width: 1.5)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: label),
                  if (count != null) TextSpan(text: ' $count', style: TextStyle(color: (selected ? Colors.white : EtkenColors.ink).withValues(alpha: 0.7))),
                ]),
                style: bodyStyle(15, weight: FontWeight.w600, color: selected ? Colors.white : EtkenColors.ink),
              ),
            ),
          ),
        ),
      );
}
