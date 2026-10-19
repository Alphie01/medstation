import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../search/drug_picker.dart';

class _Tool {
  const _Tool(this.id, this.title, this.subtitle, this.icon);
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
}

const _tools = [
  _Tool('doz', 'Kiloya göre doz', 'mg/kg, üst sınır ve sıvı hacmi', Icons.monitor_weight_outlined),
  _Tool('pediatrik', 'Pediatrik doz kontrolü', 'Günlük doz mg/kg/gün aralığında mı?', Icons.child_care_rounded),
  _Tool('bsa', 'Vücut yüzey alanı', 'Mosteller formülü', Icons.straighten_rounded),
  _Tool('birim', 'Birim dönüşümü', 'mcg · mg · g · kg', Icons.swap_horiz_rounded),
  _Tool('meq', 'mg → mEq', 'Molar kütle ve değerlik ile', Icons.science_outlined),
  _Tool('yuzde', '% (a/h) → mg/ml', 'Yüzde konsantrasyon', Icons.percent_rounded),
  _Tool('seyreltme', 'Seyreltme (C1·V1 = C2·V2)', 'Majistral hesap', Icons.water_drop_outlined),
  _Tool('alligasyon', 'Alligasyon', 'İki konsantrasyonu karıştırma', Icons.merge_type_rounded),
  _Tool('karsilastir', 'İlaç karşılaştırma', 'İki ürünü yan yana', Icons.compare_arrows_rounded),
];

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Araçlar', style: displayStyle(22, color: EtkenColors.ink)), backgroundColor: EtkenColors.bg),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          EtkenCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final (i, t) in _tools.indexed)
                ListTile(
                  shape: i == 0 ? null : const Border(top: BorderSide(color: EtkenColors.lineSoft)),
                  minVerticalPadding: 14,
                  leading: Icon(t.icon, color: EtkenColors.navy),
                  title: Text(t.title, style: bodyStyle(16, weight: FontWeight.w700)),
                  subtitle: Text(t.subtitle, style: bodyStyle(14, color: EtkenColors.muted)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/daha/araclar/${t.id}'),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          Text('Hesaplamalar adımlarıyla gösterilir; sonucu klinik bağlamla birlikte değerlendirin.',
              style: bodyStyle(13, color: EtkenColors.muted)),
        ]),
      );
}

class ToolScreen extends StatelessWidget {
  const ToolScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final t = _tools.firstWhere((t) => t.id == id, orElse: () => _tools.first);
    return Scaffold(
      appBar: AppBar(title: Text(t.title, style: displayStyle(20, color: EtkenColors.ink)), backgroundColor: EtkenColors.bg),
      body: id == 'karsilastir' ? const _Compare() : _Calculator(id: id),
    );
  }
}

enum _F { perKg, weight, maxDose, conc, concMl, daily, minKg, maxKg, height, value, mg, molar, valence, percent, c1, v1, c2, v2, high, low, target, total }

const _labels = {
  _F.perKg: 'Doz (mg/kg)',
  _F.weight: 'Kilo (kg)',
  _F.maxDose: 'Tek doz üst sınırı (mg, isteğe bağlı)',
  _F.conc: 'Konsantrasyon: mg (isteğe bağlı)',
  _F.concMl: '… her kaç ml’de',
  _F.daily: 'Reçetelenen günlük doz (mg)',
  _F.minKg: 'Alt sınır (mg/kg/gün)',
  _F.maxKg: 'Üst sınır (mg/kg/gün)',
  _F.height: 'Boy (cm)',
  _F.value: 'Değer',
  _F.mg: 'Miktar (mg)',
  _F.molar: 'Molar kütle (g/mol)',
  _F.valence: 'Değerlik',
  _F.percent: 'Yüzde (%)',
  _F.c1: 'C1 başlangıç konsantrasyonu',
  _F.v1: 'V1 alınacak hacim',
  _F.c2: 'C2 hedef konsantrasyon',
  _F.v2: 'V2 son hacim',
  _F.high: 'Yüksek konsantrasyon (%)',
  _F.low: 'Düşük konsantrasyon (%)',
  _F.target: 'Hedef konsantrasyon (%)',
  _F.total: 'Toplam miktar',
};

class _Calculator extends StatefulWidget {
  const _Calculator({required this.id});
  final String id;
  @override
  State<_Calculator> createState() => _CalculatorState();
}

class _CalculatorState extends State<_Calculator> {
  final _c = {for (final f in _F.values) f: TextEditingController()};
  MassUnit _from = MassUnit.mg, _to = MassUnit.g;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? v(_F f) => double.tryParse(_c[f]!.text.replaceAll(',', '.'));

  List<_F> get _fields => switch (widget.id) {
        'doz' => [_F.perKg, _F.weight, _F.maxDose, _F.conc, _F.concMl],
        'pediatrik' => [_F.daily, _F.weight, _F.minKg, _F.maxKg],
        'bsa' => [_F.height, _F.weight],
        'birim' => [_F.value],
        'meq' => [_F.mg, _F.molar, _F.valence],
        'yuzde' => [_F.percent],
        'seyreltme' => [_F.c1, _F.v1, _F.c2, _F.v2],
        'alligasyon' => [_F.high, _F.low, _F.target, _F.total],
        _ => const [],
      };

  (String?, CalcResult<Object>?) _compute() {
    if (_fields.every((f) => _c[f]!.text.trim().isEmpty)) return (null, null);
    switch (widget.id) {
      case 'doz':
        final r = weightBasedDose(perKg: v(_F.perKg), weightKg: v(_F.weight), maxDose: v(_F.maxDose), concAmount: v(_F.conc), concPerMl: v(_F.concMl));
        return (r is CalcOk<WeightDose> ? '${_n(r.value.dose)} mg${r.value.volumeMl == null ? '' : ' = ${_n(r.value.volumeMl!)} ml'}' : null, r);
      case 'pediatrik':
        final r = pediatricDoseCheck(dailyDose: v(_F.daily), weightKg: v(_F.weight), minPerKgDay: v(_F.minKg), maxPerKgDay: v(_F.maxKg));
        return (r is CalcOk<DoseRangeStatus>
            ? switch (r.value) { DoseRangeStatus.altinda => 'Aralığın altında', DoseRangeStatus.aralikta => 'Aralıkta', DoseRangeStatus.ustunde => 'Aralığın üstünde' }
            : null, r);
      case 'bsa':
        final r = bsaMosteller(heightCm: v(_F.height), weightKg: v(_F.weight));
        return (r is CalcOk<double> ? '${_n(r.value)} m²' : null, r);
      case 'birim':
        final r = convertMass(v(_F.value), _from, _to);
        return (r is CalcOk<double> ? '${_n(r.value, 6)} ${_to.name}' : null, r);
      case 'meq':
        final r = mgToMeq(mg: v(_F.mg), molarMass: v(_F.molar), valence: v(_F.valence)?.round());
        return (r is CalcOk<double> ? '${_n(r.value, 3)} mEq' : null, r);
      case 'yuzde':
        final r = percentToMgPerMl(v(_F.percent));
        return (r is CalcOk<double> ? '${_n(r.value)} mg/ml' : null, r);
      case 'seyreltme':
        final r = dilution(c1: v(_F.c1), v1: v(_F.v1), c2: v(_F.c2), v2: v(_F.v2));
        return (r is CalcOk<Dilution> ? 'V1 ${_n(r.value.v1)} · V2 ${_n(r.value.v2)} · seyreltici ${_n(r.value.diluent)}' : null, r);
      case 'alligasyon':
        final r = alligation(high: v(_F.high), low: v(_F.low), target: v(_F.target), total: v(_F.total));
        return (r is CalcOk<Alligation> ? 'Yüksek ${_n(r.value.highAmount)} + düşük ${_n(r.value.lowAmount)}' : null, r);
    }
    return (null, null);
  }

  static String _n(double x, [int d = 2]) {
    final s = x.toStringAsFixed(d);
    return (s.contains('.') ? s.replaceAll(RegExp(r'\.?0+$'), '') : s).replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final (headline, result) = _compute();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      if (widget.id == 'seyreltme')
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('Dört alandan birini boş bırakın; o değer hesaplanır. Birimler tutarlı olmalı.', style: bodyStyle(14, color: EtkenColors.muted)),
        ),
      if (widget.id == 'birim')
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(child: _unit('Kaynak', _from, (u) => setState(() => _from = u))),
            const SizedBox(width: 10),
            Expanded(child: _unit('Hedef', _to, (u) => setState(() => _to = u))),
          ]),
        ),
      for (final f in _fields) ...[
        TextField(
          controller: _c[f],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
          decoration: InputDecoration(labelText: _labels[f]),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 6),
      if (result is CalcError<Object>)
        EtkenCard(color: EtkenColors.riskMajorTint, child: Text(result.message, style: bodyStyle(16, weight: FontWeight.w600, color: EtkenColors.riskMajor)))
      else if (result is CalcOk<Object>)
        EtkenCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sonuç', style: bodyStyle(13, color: EtkenColors.muted)),
            const SizedBox(height: 4),
            Semantics(liveRegion: true, child: Text(headline ?? '', style: displayStyle(28, weight: FontWeight.w800, color: EtkenColors.navy))),
            const SizedBox(height: 12),
            for (final s in result.steps) Text(s.replaceAll('.', ','), style: bodyStyle(15)),
            for (final w in result.warnings) ...[
              const SizedBox(height: 8),
              Row(children: [
                const RiskBadge(Severity.onemli, compact: true),
                const SizedBox(width: 8),
                Expanded(child: Text(w, style: bodyStyle(14))),
              ]),
            ],
          ]),
        ),
    ]);
  }

  Widget _unit(String label, MassUnit v, ValueChanged<MassUnit> on) => DropdownButtonFormField<MassUnit>(
        initialValue: v,
        decoration: InputDecoration(labelText: label),
        items: [for (final u in MassUnit.values) DropdownMenuItem(value: u, child: Text(u.name))],
        onChanged: (u) => u == null ? null : on(u),
      );
}

class _Compare extends StatefulWidget {
  const _Compare();
  @override
  State<_Compare> createState() => _CompareState();
}

class _CompareState extends State<_Compare> {
  Drug? _a, _b;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String Function(Drug))>[
      ('Etken madde', (d) => d.ingredients.isEmpty ? 'Veri yok' : d.ingredients.map((i) => '${i.name} ${i.amountLabel}').join('\n')),
      ('Form', (d) => d.form ?? 'Veri yok'),
      ('Firma', (d) => d.firm ?? 'Veri yok'),
      ('Ambalaj', (d) => d.pack ?? 'Veri yok'),
      ('PSF', (d) => fmtPrice(d.psf)),
      ('ATC', (d) => d.atc ?? 'Veri yok'),
      ('Reçete', (d) => d.rxType.label),
      ('SGK', (d) => d.sgkStatus ?? 'Veri yok'),
    ];
    final same = _a != null && _b != null && _a!.equivalenceKey == _b!.equivalenceKey;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      Row(children: [
        Expanded(child: _slot(_a, (d) => setState(() => _a = d))),
        const SizedBox(width: 10),
        Expanded(child: _slot(_b, (d) => setState(() => _b = d))),
      ]),
      if (_a != null && _b != null) ...[
        const SizedBox(height: 12),
        EtkenCard(
          color: same ? EtkenColors.commercialTint : EtkenColors.riskMajorTint,
          child: Text(same ? 'Aynı etken madde, miktar ve form: eşdeğer grupta.' : 'Eşdeğer değil: bileşim, miktar veya form farklı.',
              style: bodyStyle(15, weight: FontWeight.w700)),
        ),
        const SizedBox(height: 12),
        EtkenCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final (i, (label, f)) in rows.indexed)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: EtkenColors.lineSoft))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: bodyStyle(13, color: EtkenColors.muted)),
                  const SizedBox(height: 4),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(f(_a!), style: bodyStyle(15, weight: FontWeight.w600))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(f(_b!), style: bodyStyle(15, weight: FontWeight.w600))),
                  ]),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }

  Widget _slot(Drug? d, ValueChanged<Drug> on) => EtkenCard(
        onTap: () async {
          final x = await pickDrug(context, title: 'Karşılaştırılacak ilaç');
          if (x != null) on(x);
        },
        child: SizedBox(
          height: 64,
          child: Center(
            child: Text(d?.name ?? '+ İlaç seç', textAlign: TextAlign.center, maxLines: 3,
                style: bodyStyle(15, weight: FontWeight.w700, color: d == null ? EtkenColors.muted : EtkenColors.ink)),
          ),
        ),
      );
}
