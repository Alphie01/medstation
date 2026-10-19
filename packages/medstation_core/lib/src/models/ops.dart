import 'package:meta/meta.dart';

import 'provenance.dart';

@immutable
class StockBatch {
  const StockBatch({
    required this.id,
    required this.quantity,
    this.lot,
    this.serial,
    this.expiry,
  });

  final String id;
  final String? lot;
  final String? serial;
  final DateTime? expiry;
  final int quantity;

  /// Days until expiry relative to [now]; null when expiry is unknown.
  int? daysToExpiry(DateTime now) => expiry == null
      ? null
      : DateTime(expiry!.year, expiry!.month, expiry!.day)
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;

  factory StockBatch.fromJson(Map<String, dynamic> j) => StockBatch(
        id: j['id'] as String,
        lot: j['lot'] as String?,
        serial: j['serial'] as String?,
        expiry: j['expiry'] == null ? null : DateTime.parse(j['expiry'] as String),
        quantity: j['quantity'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'lot': lot,
        'serial': serial,
        'expiry': expiry?.toIso8601String().substring(0, 10),
        'quantity': quantity,
      };
}

@immutable
class StockItem {
  const StockItem({
    required this.id,
    required this.drugId,
    required this.drugName,
    required this.batches,
    this.barcode,
    this.criticalLevel = 0,
  });

  final String id;
  final String drugId;
  final String drugName;
  final String? barcode;
  final int criticalLevel;
  final List<StockBatch> batches;

  int get quantity => batches.fold(0, (a, b) => a + b.quantity);
  bool get isOut => quantity <= 0;
  bool get isCritical => !isOut && quantity <= criticalLevel;

  factory StockItem.fromJson(Map<String, dynamic> j) => StockItem(
        id: j['id'] as String,
        drugId: j['drugId'] as String,
        drugName: j['drugName'] as String,
        barcode: j['barcode'] as String?,
        criticalLevel: j['criticalLevel'] as int? ?? 0,
        batches: (j['batches'] as List)
            .map((e) => StockBatch.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'drugId': drugId,
        'drugName': drugName,
        'barcode': barcode,
        'criticalLevel': criticalLevel,
        'quantity': quantity,
        'batches': batches.map((e) => e.toJson()).toList(),
      };
}

enum AnnouncementType {
  duyuru('Duyuru'),
  geriCekme('Geri çekme'),
  guvenlilik('Güvenlilik'),
  fiyat('Fiyat');

  const AnnouncementType(this.label);
  final String label;
}

@immutable
class Announcement {
  const Announcement({
    required this.id,
    required this.type,
    required this.title,
    required this.publishedAt,
    required this.provenance,
    this.summary,
    this.url,
  });

  final String id;
  final AnnouncementType type;
  final String title;
  final String? summary;
  final String? url;
  final DateTime publishedAt;
  final DataProvenance provenance;

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: j['id'] as String,
        type: AnnouncementType.values.byName(j['type'] as String),
        title: j['title'] as String,
        summary: j['summary'] as String?,
        url: j['url'] as String?,
        publishedAt: DateTime.parse(j['publishedAt'] as String),
        provenance:
            DataProvenance.fromJson(j['provenance'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'summary': summary,
        'url': url,
        'publishedAt': publishedAt.toUtc().toIso8601String(),
        'provenance': provenance.toJson(),
      };
}

/// A passage from a KÜB/KT document the assistant relied on.
@immutable
class Citation {
  const Citation({
    required this.chunkId,
    required this.drugName,
    required this.document,
    required this.excerpt,
    this.section,
    this.url,
    this.documentDate,
  });

  final String chunkId;
  final String drugName;

  /// "KÜB" or "KT".
  final String document;
  final String? section;
  final String excerpt;
  final String? url;
  final DateTime? documentDate;

  factory Citation.fromJson(Map<String, dynamic> j) => Citation(
        chunkId: j['chunkId'] as String,
        drugName: j['drugName'] as String,
        document: j['document'] as String,
        section: j['section'] as String?,
        excerpt: j['excerpt'] as String,
        url: j['url'] as String?,
        documentDate: j['documentDate'] == null
            ? null
            : DateTime.parse(j['documentDate'] as String),
      );

  Map<String, dynamic> toJson() => {
        'chunkId': chunkId,
        'drugName': drugName,
        'document': document,
        'section': section,
        'excerpt': excerpt,
        'url': url,
        'documentDate': documentDate?.toUtc().toIso8601String(),
      };
}

enum Confidence { yuksek, orta, dusuk, yok }

@immutable
class AssistantAnswer {
  const AssistantAnswer({
    required this.answer,
    required this.citations,
    required this.confidence,
    required this.needsVerification,
    required this.generatedAt,
  });

  final String answer;
  final List<Citation> citations;
  final Confidence confidence;
  final bool needsVerification;
  final DateTime generatedAt;

  factory AssistantAnswer.fromJson(Map<String, dynamic> j) => AssistantAnswer(
        answer: j['answer'] as String,
        citations: (j['citations'] as List)
            .map((e) => Citation.fromJson(e as Map<String, dynamic>))
            .toList(),
        confidence: Confidence.values.byName(j['confidence'] as String),
        needsVerification: j['needsVerification'] as bool,
        generatedAt: DateTime.parse(j['generatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'answer': answer,
        'citations': citations.map((e) => e.toJson()).toList(),
        'confidence': confidence.name,
        'needsVerification': needsVerification,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
      };
}
