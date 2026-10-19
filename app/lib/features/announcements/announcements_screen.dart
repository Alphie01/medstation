import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';

final announcementsProvider = FutureProvider.autoDispose.family<List<Announcement>, AnnouncementType?>((ref, t) async {
  final r = await ref.watch(apiProvider).get('/announcements', query: {if (t != null) 'type': t.name});
  return [for (final e in r['items'] as List) Announcement.fromJson(e as Map<String, dynamic>)];
});

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});
  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  AnnouncementType? _type;

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(announcementsProvider(_type));
    return Scaffold(
      appBar: AppBar(title: Text('Duyurular', style: displayStyle(22, color: EtkenColors.ink)), backgroundColor: EtkenColors.bg),
      body: RefreshIndicator(
        color: EtkenColors.coral,
        onRefresh: () async => ref.invalidate(announcementsProvider(_type)),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              FilterPill(label: 'Tümü', selected: _type == null, onTap: () => setState(() => _type = null)),
              for (final t in AnnouncementType.values) ...[
                const SizedBox(width: 8),
                FilterPill(label: t.label, selected: _type == t, onTap: () => setState(() => _type = t)),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          ...a.when(
            loading: () => const [Loading()],
            error: (e, _) => [ErrorPanel(e, onRetry: () => ref.invalidate(announcementsProvider(_type)))],
            data: (items) => items.isEmpty
                ? const [EmptyPanel(title: 'Duyuru yok', body: 'Bu türde içe aktarılmış duyuru bulunmuyor. Duyurular sunucuda TİTCK kaynağından içe aktarılır.')]
                : [
                    if (items.any((x) => x.provenance.isSample)) ...[const SampleBanner(), const SizedBox(height: 12)],
                    for (final x in items) ...[
                      EtkenCard(
                        onTap: x.url == null ? null : () => launchUrl(Uri.parse(x.url!), mode: LaunchMode.inAppBrowserView),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            RiskBadge(x.type == AnnouncementType.geriCekme
                                ? Severity.kritik
                                : x.type == AnnouncementType.guvenlilik
                                    ? Severity.onemli
                                    : Severity.bilgi, compact: true),
                            const SizedBox(width: 8),
                            Text(x.type.label, style: bodyStyle(13, weight: FontWeight.w700, color: EtkenColors.muted)),
                            const Spacer(),
                            Text(fmtDate(x.publishedAt), style: bodyStyle(13, color: EtkenColors.muted)),
                          ]),
                          const SizedBox(height: 8),
                          Text(x.title, style: bodyStyle(16, weight: FontWeight.w700, height: 1.3)),
                          if (x.summary != null) ...[const SizedBox(height: 4), Text(x.summary!, style: bodyStyle(14, color: EtkenColors.muted))],
                          const SizedBox(height: 8),
                          ProvenanceLine(x.provenance),
                        ]),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
          ),
        ]),
      ),
    );
  }
}
