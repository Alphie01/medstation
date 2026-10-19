import 'package:meta/meta.dart';

/// Where a piece of data came from. Every record shown to the pharmacist
/// carries one so the UI can show source, version and last update.
@immutable
class DataProvenance {
  const DataProvenance({
    required this.source,
    required this.version,
    required this.fetchedAt,
    this.url,
    this.isSample = false,
  });

  /// Human-readable source, e.g. "TİTCK Beşeri Tıbbi Ürün Fiyat Listesi".
  final String source;

  /// Version label of the dataset (usually the publication date).
  final String version;
  final DateTime fetchedAt;
  final String? url;

  /// True for development seed data. Production must never serve it.
  final bool isSample;

  factory DataProvenance.fromJson(Map<String, dynamic> j) => DataProvenance(
        source: j['source'] as String,
        version: j['version'] as String,
        fetchedAt: DateTime.parse(j['fetchedAt'] as String),
        url: j['url'] as String?,
        isSample: j['isSample'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'source': source,
        'version': version,
        'fetchedAt': fetchedAt.toUtc().toIso8601String(),
        if (url != null) 'url': url,
        'isSample': isSample,
      };
}

/// Reference to the exact source backing a clinical statement.
@immutable
class SourceRef {
  const SourceRef({required this.source, this.section, this.url, this.date});

  final String source;
  final String? section;
  final String? url;
  final DateTime? date;

  factory SourceRef.fromJson(Map<String, dynamic> j) => SourceRef(
        source: j['source'] as String,
        section: j['section'] as String?,
        url: j['url'] as String?,
        date: j['date'] == null ? null : DateTime.parse(j['date'] as String),
      );

  Map<String, dynamic> toJson() => {
        'source': source,
        if (section != null) 'section': section,
        if (url != null) 'url': url,
        if (date != null) 'date': date!.toUtc().toIso8601String(),
      };
}
