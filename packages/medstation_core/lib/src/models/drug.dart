import 'package:meta/meta.dart';

import 'provenance.dart';
import 'text.dart';

/// Prescription colour classes used in Türkiye.
enum RxType {
  normal('Normal reçete'),
  kirmizi('Kırmızı reçete'),
  yesil('Yeşil reçete'),
  mor('Mor reçete'),
  turuncu('Turuncu reçete'),
  receteSiz('Reçetesiz'),
  bilinmiyor('Reçete türü bilinmiyor');

  const RxType(this.label);
  final String label;

  static RxType parse(String? v) => RxType.values.firstWhere(
        (e) => e.name == v,
        orElse: () => RxType.bilinmiyor,
      );
}

/// Coarse dosage-form groups used for filtering (reference: Tümü/Tablet/Sıvı).
enum FormGroup {
  tablet('Tablet'),
  sivi('Sıvı'),
  parenteral('Enjeksiyon'),
  topikal('Topikal'),
  diger('Diğer');

  const FormGroup(this.label);
  final String label;

  static FormGroup parse(String? v) =>
      FormGroup.values.firstWhere((e) => e.name == v, orElse: () => diger);

  /// Best-effort classification from a TİTCK form string. Unknown forms fall
  /// into [diger] rather than being guessed.
  static FormGroup fromFormText(String form) {
    final f = searchFold(form);
    if (RegExp(r'tablet|kapsul|draje|pastil').hasMatch(f)) return tablet;
    if (RegExp(r'surup|suspansiyon|solusyon|damla|eliksir|sase')
        .hasMatch(f)) {
      return sivi;
    }
    if (RegExp(r'enjeksiyon|infuzyon|ampul|flakon').hasMatch(f)) {
      return parenteral;
    }
    if (RegExp(r'krem|merhem|jel|pomad|losyon|sprey').hasMatch(f)) {
      return topikal;
    }
    return diger;
  }
}

/// Market status from the SKRS e-Reçete list.
enum MarketStatus {
  aktif('Aktif'),
  pasif('Pasif'),
  bilinmiyor('Bilinmiyor');

  const MarketStatus(this.label);
  final String label;

  static MarketStatus parse(String? v) =>
      MarketStatus.values.firstWhere((e) => e.name == v, orElse: () => bilinmiyor);
}

/// License suspension codes as published in the TİTCK licensed products list.
enum LicenseStatus {
  gecerli(0, 'Ruhsat geçerli'),
  madde23Askida(1, 'Ruhsat askıda (Madde 23)'),
  farmakovijilansAskida(2, 'Ruhsat askıda (farmakovijilans)'),
  madde22Askida(3, 'Ruhsat askıda (Madde 22)'),
  bilinmiyor(-1, 'Ruhsat durumu bilinmiyor');

  const LicenseStatus(this.code, this.label);
  final int code;
  final String label;

  bool get suspended => code > 0;

  static LicenseStatus fromCode(int? c) =>
      LicenseStatus.values.firstWhere((e) => e.code == c, orElse: () => bilinmiyor);
}

@immutable
class DrugIngredient {
  const DrugIngredient({
    required this.name,
    this.amount,
    this.unit,
    this.perVolumeMl,
  });

  /// Ingredient name as published (e.g. "amoksisilin trihidrat").
  final String name;

  /// Amount per unit dose (tablet) or per [perVolumeMl] ml. Null when the
  /// source does not state it; never guessed.
  final double? amount;
  final String? unit;
  final double? perVolumeMl;

  String get key => ingredientKey(name);

  String get amountLabel {
    if (amount == null || unit == null) return 'Veri yok';
    final a = amount! == amount!.roundToDouble()
        ? amount!.toStringAsFixed(0)
        : amount!.toString();
    if (perVolumeMl != null) {
      final v = perVolumeMl! == perVolumeMl!.roundToDouble()
          ? perVolumeMl!.toStringAsFixed(0)
          : perVolumeMl!.toString();
      return '$a $unit/$v ml';
    }
    return '$a $unit';
  }

  factory DrugIngredient.fromJson(Map<String, dynamic> j) => DrugIngredient(
        name: j['name'] as String,
        amount: (j['amount'] as num?)?.toDouble(),
        unit: j['unit'] as String?,
        perVolumeMl: (j['perVolumeMl'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'unit': unit,
        'perVolumeMl': perVolumeMl,
      };
}

@immutable
class Drug {
  const Drug({
    required this.id,
    required this.name,
    required this.ingredients,
    required this.provenance,
    this.barcode,
    this.firm,
    this.form,
    this.strength,
    this.pack,
    this.atc,
    this.rxType = RxType.bilinmiyor,
    this.sgkStatus,
    this.psf,
    this.equivalenceCode,
    this.storage,
    this.kubUrl,
    this.ktUrl,
    this.recalled = false,
    this.compositionText,
    this.marketStatus = MarketStatus.bilinmiyor,
    this.licenseStatus = LicenseStatus.bilinmiyor,
  });

  final String id;
  final String? barcode;
  final String name;
  final String? firm;
  final String? form;
  final String? strength;
  final String? pack;
  final String? atc;
  final RxType rxType;

  /// SGK reimbursement status text as published. Null = unknown.
  final String? sgkStatus;

  /// Pharmacy sale price (PSF) in TRY. Null = unknown.
  final double? psf;

  /// TİTCK equivalence group code when published.
  final String? equivalenceCode;
  final String? storage;
  final String? kubUrl;
  final String? ktUrl;
  final bool recalled;

  /// Composition exactly as published, shown alongside parsed ingredients
  /// (and instead of them when the source text could not be parsed).
  final String? compositionText;
  final MarketStatus marketStatus;
  final LicenseStatus licenseStatus;
  final List<DrugIngredient> ingredients;
  final DataProvenance provenance;

  FormGroup get formGroup =>
      form == null ? FormGroup.diger : FormGroup.fromFormText(form!);

  Set<String> get ingredientKeys => ingredients.map((i) => i.key).toSet();

  /// Key for "tam eşdeğer" grouping: same ingredient set, same amounts, same
  /// form group. When TİTCK publishes an equivalence code it takes priority.
  String get equivalenceKey {
    if (equivalenceCode != null && equivalenceCode!.isNotEmpty) {
      return 'titck:$equivalenceCode';
    }
    final parts = ingredients
        .map((i) => '${baseIngredient(i.name)}=${i.amount}${i.unit}/${i.perVolumeMl}')
        .toList()
      ..sort();
    return '${parts.join('+')}|${formGroup.name}';
  }

  factory Drug.fromJson(Map<String, dynamic> j) => Drug(
        id: j['id'] as String,
        barcode: j['barcode'] as String?,
        name: j['name'] as String,
        firm: j['firm'] as String?,
        form: j['form'] as String?,
        strength: j['strength'] as String?,
        pack: j['pack'] as String?,
        atc: j['atc'] as String?,
        rxType: RxType.parse(j['rxType'] as String?),
        sgkStatus: j['sgkStatus'] as String?,
        psf: (j['psf'] as num?)?.toDouble(),
        equivalenceCode: j['equivalenceCode'] as String?,
        storage: j['storage'] as String?,
        kubUrl: j['kubUrl'] as String?,
        ktUrl: j['ktUrl'] as String?,
        recalled: j['recalled'] as bool? ?? false,
        compositionText: j['compositionText'] as String?,
        marketStatus: MarketStatus.parse(j['marketStatus'] as String?),
        licenseStatus: LicenseStatus.fromCode(j['licenseStatus'] as int?),
        ingredients: (j['ingredients'] as List)
            .map((e) => DrugIngredient.fromJson(e as Map<String, dynamic>))
            .toList(),
        provenance:
            DataProvenance.fromJson(j['provenance'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'barcode': barcode,
        'name': name,
        'firm': firm,
        'form': form,
        'strength': strength,
        'pack': pack,
        'atc': atc,
        'rxType': rxType.name,
        'sgkStatus': sgkStatus,
        'psf': psf,
        'equivalenceCode': equivalenceCode,
        'storage': storage,
        'kubUrl': kubUrl,
        'ktUrl': ktUrl,
        'recalled': recalled,
        'compositionText': compositionText,
        'marketStatus': marketStatus.name,
        'licenseStatus': licenseStatus.code,
        'formGroup': formGroup.name,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
        'provenance': provenance.toJson(),
      };
}
