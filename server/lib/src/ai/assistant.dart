import 'package:medstation_core/medstation_core.dart';
import 'package:postgres/postgres.dart';

import '../db.dart';
import '../http.dart';
import 'openai.dart';
import 'redact.dart';

const _instructions = '''
Sen eczacılara yardımcı olan bir ilaç bilgi asistanısın. Kurallar:
- YALNIZCA verilen KÜB/KT pasajlarındaki bilgiyle yanıt ver. Kendi bilgini ekleme.
- Her cümlenin sonuna dayandığın pasajın kimliğini köşeli parantezle yaz, örn. [c3]. Kimliği olmayan cümle yazma.
- "citations" alanına kullandığın tüm pasaj kimliklerini yaz.
- Pasajlar soruyu yanıtlamaya yetmiyorsa bunu açıkça söyle ve "insufficient" alanını true yap.
- Klinik karar verme; eczacının değerlendirmesi gereken noktaları belirt.
- Yalnızca Türkçe yaz; İngilizce kelime kullanma. Kısa ve net ol. Doz ve birimleri pasajdaki gibi aktar.
''';

const _schema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['answer', 'citations', 'confidence', 'insufficient'],
  'properties': {
    'answer': {'type': 'string'},
    'citations': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'confidence': {
      'type': 'string',
      'enum': ['yuksek', 'orta', 'dusuk'],
    },
    'insufficient': {'type': 'boolean'},
  },
};

class AssistantService {
  AssistantService(this.db, this.ai, {this.maxDistance = 0.65, this.topK = 8});
  final Db db;
  final OpenAiClient? ai;

  /// Cosine distance above which a passage is considered unrelated.
  final double maxDistance;
  final int topK;

  static AssistantAnswer _noAnswer(String text) => AssistantAnswer(
        answer: text,
        citations: const [],
        confidence: Confidence.yok,
        needsVerification: true,
        generatedAt: DateTime.now().toUtc(),
      );

  /// [onStage] reports progress ("retrieving", "generating",
  /// "validating") so clients can show what is happening; the answer itself
  /// is only released after citation validation.
  Future<AssistantAnswer> ask(String question,
      {List<String> drugIds = const [], void Function(String stage, {int? passages})? onStage}) async {
    final client = ai;
    if (client == null) {
      throw ApiError(503, 'assistant_unavailable', 'AI asistan yapılandırılmamış');
    }
    final clean = redactPii(question.trim());
    if (clean.isEmpty) throw ApiError.badRequest('Soru boş olamaz');
    if (clean.length > 2000) throw ApiError.badRequest('Soru 2000 karakteri aşamaz');

    onStage?.call('retrieving');
    final emb = (await client.embed([clean])).single;
    final rows = await db.execute(
      Sql.named('''
        SELECT c.id, c.drug_name, c.document, c.section, c.url, c.document_date, c.content,
               c.embedding <=> CAST(@e AS vector) AS dist
        FROM doc_chunks c JOIN data_sources s ON s.id = c.source_id AND s.active
        ${drugIds.isEmpty ? '' : '''WHERE c.drug_id = ANY(@ids:_text) OR EXISTS (
          SELECT 1 FROM drugs d WHERE d.id = ANY(@ids:_text) AND d.name_fold LIKE c.name_fold || '%')'''}
        ORDER BY dist LIMIT @k'''),
      parameters: {'e': '[${emb.join(',')}]', 'ids': ?(drugIds.isEmpty ? null : drugIds), 'k': topK},
    );
    final chunks = <String, Citation>{};
    for (final r in rows) {
      final m = r.toColumnMap();
      if ((m['dist'] as num).toDouble() > maxDistance) continue;
      chunks[m['id'] as String] = Citation(
        chunkId: m['id'] as String,
        drugName: m['drug_name'] as String,
        document: m['document'] as String,
        section: m['section'] as String?,
        excerpt: m['content'] as String,
        url: m['url'] as String?,
        documentDate: m['document_date'] as DateTime?,
      );
    }
    if (chunks.isEmpty) {
      return _noAnswer('Yüklü KÜB/KT kaynaklarında bu soruya yanıt bulunamadı. '
          'Lütfen ilgili ürünün güncel KÜB metnini kontrol edin.');
    }

    onStage?.call('generating', passages: chunks.length);
    // Short local aliases keep the prompt small and make invented ids easy to spot.
    final alias = <String, String>{};
    final buf = StringBuffer('Pasajlar:\n');
    var n = 1;
    for (final c in chunks.values) {
      final a = 'c${n++}';
      alias[a] = c.chunkId;
      buf.writeln('[$a] ${c.drugName} — ${c.document}${c.section == null ? '' : ' ${c.section}'}');
      buf.writeln(c.excerpt);
      buf.writeln();
    }
    buf.writeln('Soru: $clean');

    final out = await client.structured(
      instructions: _instructions,
      input: buf.toString(),
      schemaName: 'pharmacist_answer',
      schema: _schema,
    );
    onStage?.call('validating');
    return validate(out, alias, chunks);
  }

  /// Keeps only citations that refer to retrieved passages. An answer left
  /// with no valid citation is withheld rather than shown unsourced.
  static AssistantAnswer validate(
    Map<String, dynamic> out,
    Map<String, String> alias,
    Map<String, Citation> chunks,
  ) {
    final cited = <Citation>[];
    for (final a in (out['citations'] as List? ?? const []).cast<String>()) {
      final key = a.replaceAll(RegExp(r'[\[\]\s]'), '');
      final id = alias[key];
      if (id != null && cited.every((c) => c.chunkId != id)) cited.add(chunks[id]!);
    }
    final text = (out['answer'] as String? ?? '').trim();
    final insufficient = out['insufficient'] == true;
    // "Not in the passages" must not list unrelated passages as sources.
    if (insufficient) {
      return _noAnswer(text.isEmpty
          ? 'Yüklü KÜB/KT kaynaklarında bu soruya yeterli yanıt bulunamadı.'
          : text.replaceAll(RegExp(r'\s?\[c?\d+\]'), ''));
    }
    if (cited.isEmpty) {
      return _noAnswer(insufficient && text.isNotEmpty
          ? text
          : 'Yanıt kaynak pasajlarla doğrulanamadığı için gösterilmiyor.');
    }
    // Renumber markers to the returned citation order; drop unknown ones.
    final shown = text.replaceAllMapped(RegExp(r'\s?\[(c\d+)\]'), (m) {
      final id = alias[m[1]];
      final i = cited.indexWhere((c) => c.chunkId == id);
      return i < 0 ? '' : ' [${i + 1}]';
    });
    final conf = Confidence.values.asNameMap()[out['confidence']] ?? Confidence.dusuk;
    return AssistantAnswer(
      answer: shown,
      citations: cited,
      confidence: insufficient ? Confidence.dusuk : conf,
      needsVerification: insufficient || conf != Confidence.yuksek,
      generatedAt: DateTime.now().toUtc(),
    );
  }
}
