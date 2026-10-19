import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';

class ChatMsg {
  ChatMsg.user(this.text) : answer = null, error = null;
  ChatMsg.answer(this.answer) : text = null, error = null;
  ChatMsg.error(this.error) : text = null, answer = null;
  final String? text;
  final AssistantAnswer? answer;
  final String? error;
}

/// Conversation kept in memory only for the session.
class AssistantChat extends Notifier<List<ChatMsg>> {
  @override
  List<ChatMsg> build() => const [];
  void add(ChatMsg m) => state = [...state, m];
  void clear() => state = const [];
}

final _chatProvider = NotifierProvider<AssistantChat, List<ChatMsg>>(AssistantChat.new);

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key, this.drugId, this.drugName, this.question});
  final String? drugId;
  final String? drugName;

  /// Pre-filled question (e.g. from a checklist finding); sent on open.
  final String? question;
  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  String? _stage;
  late String? _drugId = widget.drugId;
  late String? _drugName = widget.drugName;

  @override
  void initState() {
    super.initState();
    if (widget.question != null) WidgetsBinding.instance.addPostFrameCallback((_) => _send(widget.question));
  }

  @override
  void didUpdateWidget(AssistantScreen old) {
    super.didUpdateWidget(old);
    if (widget.drugId != old.drugId) {
      _drugId = widget.drugId;
      _drugName = widget.drugName;
    }
    if (widget.question != null && widget.question != old.question) _send(widget.question);
  }

  static String _stageText(String stage, int? passages) => switch (stage) {
        'retrieving' => 'KÜB/KT kaynakları taranıyor…',
        'generating' => '${passages ?? ''} kaynak pasajdan yanıt hazırlanıyor…',
        'validating' => 'Kaynak gösterimleri doğrulanıyor…',
        _ => 'Çalışıyor…',
      };

  @override
  void dispose() {
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final q = (preset ?? _c.text).trim();
    if (q.isEmpty || _sending) return;
    final chat = ref.read(_chatProvider.notifier);
    chat.add(ChatMsg.user(q));
    _c.clear();
    setState(() => _sending = true);
    _toBottom();
    final body = {'question': q, if (_drugId != null) 'drugIds': [_drugId]};
    final api = ref.read(apiProvider);
    try {
      AssistantAnswer? answer;
      try {
        await for (final (event, data) in api.events('/assistant/ask/stream', body)) {
          if (event == 'stage' && mounted) setState(() => _stage = _stageText(data['stage'] as String, data['passages'] as int?));
          if (event == 'result') answer = AssistantAnswer.fromJson(data);
          if (event == 'error') throw ApiException(data['code'] as String, data['message'] as String);
        }
      } on ApiException catch (e) {
        if (e.code != 'unknown') rethrow;
        // Stream failed before any event (e.g. expired session): the plain
        // endpoint goes through the normal refresh flow.
        answer = AssistantAnswer.fromJson(await api.post('/assistant/ask', body));
      }
      if (answer != null) chat.add(ChatMsg.answer(answer));
    } on ApiException catch (e) {
      chat.add(ChatMsg.error(e.message));
    } finally {
      if (mounted) setState(() => (_sending = false, _stage = null));
      _toBottom();
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final msgs = ref.watch(_chatProvider);
    final meta = ref.watch(metaProvider).value;
    final docs = meta?.source('documents');

    return Scaffold(
      body: Column(children: [
        HeroHeader(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Semantics(header: true, child: Text('Eczacı asistanı', style: displayStyle(30, weight: FontWeight.w800, color: Colors.white)))),
              if (msgs.isNotEmpty)
                HeaderIconButton(icon: Icons.refresh_rounded, label: 'Yeni sohbet', onPressed: ref.read(_chatProvider.notifier).clear),
            ]),
            const SizedBox(height: 6),
            Text('Yanıtlar yalnızca yüklü KÜB/KT metinlerinden, kaynak göstererek verilir.',
                style: bodyStyle(14, color: Colors.white.withValues(alpha: 0.8))),
            if (_drugName != null) ...[
              const SizedBox(height: 12),
              InputChip(
                label: Text('Bağlam: $_drugName'),
                onDeleted: () => setState(() => (_drugId = null, _drugName = null)),
              ),
            ],
          ]),
        ),
        Expanded(
          child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
            if (meta != null && !meta.assistantAvailable)
              const EmptyPanel(title: 'Asistan yapılandırılmamış', body: 'Sunucuda OpenAI anahtarı tanımlı değil. Yöneticinize başvurun.')
            else if (msgs.isEmpty) ...[
              EtkenCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Örnek sorular', style: bodyStyle(15, weight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final s in const [
                    'Böbrek yetmezliğinde doz ayarlaması gerekir mi?',
                    'Gebelikte kullanımı hakkında ne söyleniyor?',
                    'Bilinen kontrendikasyonları nelerdir?',
                    'Saklama koşulları nedir?',
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s, style: bodyStyle(15)),
                      trailing: const Icon(Icons.north_east_rounded, size: 18),
                      onTap: () => _send(s),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              ProvenanceLine(
                docs == null
                    ? null
                    : DataProvenance(source: docs['source'] as String, version: docs['version'] as String,
                        fetchedAt: DateTime.parse(docs['fetchedAt'] as String)),
                prefix: 'Belge kütüphanesi',
              ),
            ],
            for (final m in msgs) ...[
              if (m.text != null) _UserBubble(m.text!),
              if (m.answer != null) _AnswerCard(m.answer!),
              if (m.error != null) ErrorPanel(ApiException('assistant', m.error!)),
              const SizedBox(height: 12),
            ],
            if (_sending)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const LinearProgressIndicator(color: EtkenColors.coral),
                  const SizedBox(height: 8),
                  Semantics(liveRegion: true, child: Text(_stage ?? 'Gönderiliyor…', style: bodyStyle(14, color: EtkenColors.muted))),
                ]),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Sorunuz (hasta kimliği yazmayın)'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                style: IconButton.styleFrom(backgroundColor: EtkenColors.navy, minimumSize: const Size(52, 52)),
                tooltip: 'Gönder',
                icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: EtkenColors.navy, borderRadius: BorderRadius.circular(20)),
          child: Text(text, style: bodyStyle(16, color: Colors.white)),
        ),
      );
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard(this.a);
  final AssistantAnswer a;

  String get _confidence => switch (a.confidence) {
        Confidence.yuksek => 'Güven: yüksek',
        Confidence.orta => 'Güven: orta',
        Confidence.dusuk => 'Güven: düşük',
        Confidence.yok => 'Kaynakta bulunamadı',
      };

  void _open(BuildContext context, int i, Citation c) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (_, s) => ListView(controller: s, padding: const EdgeInsets.all(20), children: [
            Text('[${i + 1}] ${c.drugName}', style: displayStyle(20, color: EtkenColors.ink)),
            Text('${c.document}${c.section == null ? '' : ' · ${c.section}'}${c.documentDate == null ? '' : ' · ${fmtDate(c.documentDate!)}'}',
                style: bodyStyle(14, color: EtkenColors.muted)),
            const SizedBox(height: 14),
            SelectableText(c.excerpt, style: bodyStyle(16)),
            if (c.url != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(c.url!), mode: LaunchMode.inAppBrowserView),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Belgenin tamamını aç'),
              ),
            ],
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => EtkenCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            RiskBadge(a.confidence == Confidence.yuksek ? Severity.bilgi : Severity.dogrulanamadi, compact: true),
            Text(_confidence, style: bodyStyle(13, weight: FontWeight.w600, color: EtkenColors.muted)),
          ]),
          const SizedBox(height: 10),
          SelectableText(a.answer, style: bodyStyle(16, height: 1.45)),
          if (a.citations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Kaynaklar', style: bodyStyle(13, weight: FontWeight.w700, color: EtkenColors.muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < a.citations.length; i++)
                ActionChip(
                  avatar: CircleAvatar(backgroundColor: EtkenColors.navy, child: Text('${i + 1}', style: bodyStyle(11, color: Colors.white))),
                  label: Text('${a.citations[i].drugName} · ${a.citations[i].document}${a.citations[i].section == null ? '' : ' ${a.citations[i].section!.split(' ').first}'}'),
                  onPressed: () => _open(context, i, a.citations[i]),
                ),
            ]),
          ],
          if (a.needsVerification) ...[
            const SizedBox(height: 10),
            Text('Yanıtı kaynak metinle doğrulayın.', style: bodyStyle(13, weight: FontWeight.w600, color: EtkenColors.riskMajor)),
          ],
          const SizedBox(height: 8),
          Text('Oluşturulma: ${fmtDateTime(a.generatedAt)} · Klinik karar eczacıya aittir.', style: bodyStyle(12, color: EtkenColors.muted)),
        ]),
      );
}
