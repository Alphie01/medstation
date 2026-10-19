import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Result of a calculator. Invalid input yields [CalcError] with a message,
/// never a silent default value.
sealed class CalcResult<T> {
  const CalcResult();
}

@immutable
class CalcOk<T> extends CalcResult<T> {
  const CalcOk(this.value, {this.steps = const [], this.warnings = const []});
  final T value;

  /// Human-readable working, shown so the pharmacist can verify.
  final List<String> steps;
  final List<String> warnings;
}

@immutable
class CalcError<T> extends CalcResult<T> {
  const CalcError(this.message);
  final String message;
}

String _n(double v, [int digits = 2]) {
  final s = v.toStringAsFixed(digits);
  return s.contains('.') ? s.replaceAll(RegExp(r'\.?0+$'), '') : s;
}

CalcError<T>? _positive<T>(Map<String, double?> fields) {
  for (final e in fields.entries) {
    final v = e.value;
    if (v == null) return CalcError('${e.key} girilmedi');
    if (v.isNaN || v.isInfinite || v <= 0) {
      return CalcError('${e.key} sıfırdan büyük olmalı');
    }
  }
  return null;
}

@immutable
class WeightDose {
  const WeightDose({required this.dose, required this.capped, this.volumeMl});
  final double dose;
  final bool capped;
  final double? volumeMl;
}

/// mg/kg dose, optionally capped at [maxDose] and converted to a volume for
/// a liquid of [concAmount] per [concPerMl] ml.
CalcResult<WeightDose> weightBasedDose({
  required double? perKg,
  required double? weightKg,
  double? maxDose,
  double? concAmount,
  double? concPerMl,
  String unit = 'mg',
}) {
  final err = _positive<WeightDose>({'Doz (/kg)': perKg, 'Kilo': weightKg});
  if (err != null) return err;
  if (weightKg! > 250) return const CalcError('Kilo 250 kg üzerinde olamaz');
  if (maxDose != null && maxDose <= 0) {
    return const CalcError('Üst sınır sıfırdan büyük olmalı');
  }
  if ((concAmount == null) != (concPerMl == null)) {
    return const CalcError('Konsantrasyonun iki alanı da girilmeli');
  }
  if (concAmount != null && (concAmount <= 0 || concPerMl! <= 0)) {
    return const CalcError('Konsantrasyon sıfırdan büyük olmalı');
  }
  final raw = perKg! * weightKg;
  final capped = maxDose != null && raw > maxDose;
  final dose = capped ? maxDose : raw;
  final steps = ['${_n(perKg)} $unit/kg × ${_n(weightKg)} kg = ${_n(raw)} $unit'];
  final warnings = <String>[];
  if (capped) {
    steps.add('Üst sınır ${_n(maxDose)} $unit uygulandı');
    warnings.add('Hesaplanan doz üst sınırı aşıyor; sınır değeri gösteriliyor.');
  }
  double? vol;
  if (concAmount != null) {
    vol = dose / concAmount * concPerMl!;
    steps.add('${_n(dose)} $unit ÷ (${_n(concAmount)} $unit/${_n(concPerMl)} ml) '
        '= ${_n(vol)} ml');
  }
  return CalcOk(WeightDose(dose: dose, capped: capped, volumeMl: vol),
      steps: steps, warnings: warnings);
}

enum DoseRangeStatus { altinda, aralikta, ustunde }

/// Checks a prescribed daily dose against a mg/kg/day range.
CalcResult<DoseRangeStatus> pediatricDoseCheck({
  required double? dailyDose,
  required double? weightKg,
  required double? minPerKgDay,
  required double? maxPerKgDay,
  String unit = 'mg',
}) {
  final err = _positive<DoseRangeStatus>({
    'Günlük doz': dailyDose,
    'Kilo': weightKg,
    'Alt sınır': minPerKgDay,
    'Üst sınır': maxPerKgDay,
  });
  if (err != null) return err;
  if (minPerKgDay! > maxPerKgDay!) {
    return const CalcError('Alt sınır üst sınırdan büyük olamaz');
  }
  final perKg = dailyDose! / weightKg!;
  final lo = minPerKgDay * weightKg, hi = maxPerKgDay * weightKg;
  final status = perKg < minPerKgDay
      ? DoseRangeStatus.altinda
      : perKg > maxPerKgDay
          ? DoseRangeStatus.ustunde
          : DoseRangeStatus.aralikta;
  return CalcOk(status, steps: [
    '${_n(dailyDose)} $unit ÷ ${_n(weightKg)} kg = ${_n(perKg)} $unit/kg/gün',
    'Aralık: ${_n(lo)}–${_n(hi)} $unit/gün '
        '(${_n(minPerKgDay)}–${_n(maxPerKgDay)} $unit/kg/gün)',
  ]);
}

/// Body surface area, Mosteller: √(cm × kg / 3600).
CalcResult<double> bsaMosteller({
  required double? heightCm,
  required double? weightKg,
}) {
  final err = _positive<double>({'Boy': heightCm, 'Kilo': weightKg});
  if (err != null) return err;
  if (heightCm! > 250) return const CalcError('Boy 250 cm üzerinde olamaz');
  final v = math.sqrt(heightCm * weightKg! / 3600);
  return CalcOk(v, steps: [
    '√(${_n(heightCm)} × ${_n(weightKg)} / 3600) = ${_n(v)} m²',
  ]);
}

enum MassUnit {
  mcg(1e-6),
  mg(1e-3),
  g(1),
  kg(1e3);

  const MassUnit(this.grams);
  final double grams;
}

CalcResult<double> convertMass(double? value, MassUnit from, MassUnit to) {
  if (value == null) return const CalcError('Değer girilmedi');
  if (value < 0 || value.isNaN) return const CalcError('Değer negatif olamaz');
  final v = value * from.grams / to.grams;
  return CalcOk(v, steps: ['${_n(value, 6)} ${from.name} = ${_n(v, 6)} ${to.name}']);
}

/// mg → mEq using molar mass (g/mol) and valence.
CalcResult<double> mgToMeq({
  required double? mg,
  required double? molarMass,
  required int? valence,
}) {
  final err = _positive<double>(
      {'Miktar': mg, 'Molar kütle': molarMass, 'Değerlik': valence?.toDouble()});
  if (err != null) return err;
  final v = mg! * valence! / molarMass!;
  return CalcOk(v, steps: [
    '${_n(mg)} mg × $valence ÷ ${_n(molarMass)} g/mol = ${_n(v, 3)} mEq',
  ]);
}

/// % w/v → mg/ml (1 % = 10 mg/ml).
CalcResult<double> percentToMgPerMl(double? percent) {
  final err = _positive<double>({'Yüzde': percent});
  if (err != null) return err;
  if (percent! > 100) return const CalcError('Yüzde 100\'den büyük olamaz');
  return CalcOk(percent * 10, steps: ['%${_n(percent)} = ${_n(percent * 10)} mg/ml']);
}

@immutable
class Dilution {
  const Dilution({required this.c1, required this.v1, required this.c2, required this.v2});
  final double c1, v1, c2, v2;
  double get diluent => v2 - v1;
}

/// C1·V1 = C2·V2 — exactly one argument must be null and is solved for.
CalcResult<Dilution> dilution({double? c1, double? v1, double? c2, double? v2}) {
  final vals = [c1, v1, c2, v2];
  if (vals.where((v) => v == null).length != 1) {
    return const CalcError('Dört değerden tam olarak biri boş bırakılmalı');
  }
  if (vals.whereType<double>().any((v) => v <= 0)) {
    return const CalcError('Değerler sıfırdan büyük olmalı');
  }
  final r = Dilution(
    c1: c1 ?? c2! * v2! / v1!,
    v1: v1 ?? c2! * v2! / c1!,
    c2: c2 ?? c1! * v1! / v2!,
    v2: v2 ?? c1! * v1! / c2!,
  );
  if (r.c2 > r.c1) {
    return const CalcError('Son konsantrasyon başlangıçtan büyük olamaz');
  }
  return CalcOk(r, steps: [
    '${_n(r.c1)} × ${_n(r.v1)} = ${_n(r.c2)} × ${_n(r.v2)}',
    'Seyreltici: ${_n(r.diluent)}',
  ]);
}

@immutable
class Alligation {
  const Alligation({required this.highAmount, required this.lowAmount});
  final double highAmount, lowAmount;
}

/// Mixing a high and a low concentration to reach [target] in [total].
CalcResult<Alligation> alligation({
  required double? high,
  required double? low,
  required double? target,
  required double? total,
}) {
  if (high == null || low == null || target == null || total == null) {
    return const CalcError('Tüm alanlar girilmeli');
  }
  if (low < 0 || total <= 0) return const CalcError('Değerler geçersiz');
  if (!(high > target && target > low)) {
    return const CalcError('Hedef, iki konsantrasyonun arasında olmalı');
  }
  final hp = target - low, lp = high - target;
  final h = total * hp / (hp + lp);
  return CalcOk(Alligation(highAmount: h, lowAmount: total - h), steps: [
    'Yüksek: ${_n(target)} − ${_n(low)} = ${_n(hp)} pay',
    'Düşük: ${_n(high)} − ${_n(target)} = ${_n(lp)} pay',
    'Yüksek ${_n(h)}, düşük ${_n(total - h)}',
  ]);
}
