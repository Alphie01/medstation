import 'package:medstation_core/medstation_core.dart';

import 'http.dart';

/// Source of e-prescription contents.
///
/// MEDULA / e-Nabız access is only possible through an officially authorised
/// integration (SGK protocol or a licensed pharmacy software provider).
/// This interface is the seam where that integration plugs in; nothing here
/// scrapes or emulates official systems.
abstract class PrescriptionSource {
  bool get available;
  Future<List<PrescriptionLine>> fetch(String prescriptionCode, {required String pharmacyId});
}

class DisabledMedulaSource implements PrescriptionSource {
  const DisabledMedulaSource();

  @override
  bool get available => false;

  @override
  Future<List<PrescriptionLine>> fetch(String code, {required String pharmacyId}) =>
      throw ApiError(
        501,
        'integration_not_authorized',
        'MEDULA entegrasyonu bu eczane için yetkilendirilmemiş. e-Reçete içeriğini '
            'yetkili eczane yazılımınızdan kontrol edin veya ilaçları elle ekleyin.',
      );
}
