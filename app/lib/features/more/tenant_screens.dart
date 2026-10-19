import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';

final _usersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
    (ref) async => ((await ref.watch(apiProvider).get('/pharmacy/users'))['items'] as List).cast());

final _catalogProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
    (ref) async => ((await ref.watch(apiProvider).get('/catalog'))['items'] as List).cast());

const _roleLabels = {'eczaci': 'Eczacı', 'teknisyen': 'Teknisyen', 'admin': 'Yönetici'};

/// Users of this pharmacy. They share stock, catalog and check history; each
/// change is recorded with the user who made it.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const _NewUserDialog());
    if (ok == true) ref.invalidate(_usersProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(_usersProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Eczane kullanıcıları', style: displayStyle(20, color: EtkenColors.ink)), backgroundColor: EtkenColors.bg),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: EtkenColors.navy,
        foregroundColor: Colors.white,
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Kullanıcı ekle'),
      ),
      body: u.when(
        loading: () => const Loading(),
        error: (e, _) => ErrorPanel(e, onRetry: () => ref.invalidate(_usersProvider)),
        data: (items) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
          Text('Aynı eczanedeki kullanıcılar stoğu, kataloğu ve reçete kontrol geçmişini ortak kullanır. Her işlem yapan kullanıcıyla kaydedilir.',
              style: bodyStyle(13, color: EtkenColors.muted)),
          const SizedBox(height: 12),
          EtkenCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final (i, x) in items.indexed)
                Container(
                  decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: EtkenColors.lineSoft))),
                  child: SwitchListTile(
                    title: Text(x['fullName'] as String, style: bodyStyle(15, weight: FontWeight.w700)),
                    subtitle: Text('${x['email']} · ${_roleLabels[x['role']] ?? x['role']}', style: bodyStyle(13, color: EtkenColors.muted)),
                    value: x['active'] as bool,
                    onChanged: (v) async {
                      try {
                        await ref.read(apiProvider).send('PATCH', '/pharmacy/users/${x['id']}', {'active': v});
                        ref.invalidate(_usersProvider);
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    },
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _NewUserDialog extends ConsumerStatefulWidget {
  const _NewUserDialog();
  @override
  ConsumerState<_NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends ConsumerState<_NewUserDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  String _role = 'teknisyen';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => (_busy = true, _error = null));
    try {
      await ref.read(apiProvider).post('/pharmacy/users', {
        'fullName': _name.text.trim(),
        'email': _email.text.trim(),
        'password': _pass.text,
        'role': _role,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Yeni kullanıcı'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Ad soyad')),
            const SizedBox(height: 10),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-posta')),
            const SizedBox(height: 10),
            TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Geçici parola (en az 10 karakter)')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _role,
              style: bodyStyle(16, color: EtkenColors.ink),
              decoration: const InputDecoration(labelText: 'Rol'),
              items: [for (final e in _roleLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: bodyStyle(14, color: EtkenColors.riskCritical))],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Oluştur')),
        ],
      );
}

/// The pharmacy's own supportive (commercial) products, suggested in a
/// separate, labelled section when a prescribed drug matches the trigger.
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(_catalogProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Destekleyici ürünler', style: displayStyle(20, color: EtkenColors.ink)), backgroundColor: EtkenColors.bg),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: EtkenColors.commercial,
        foregroundColor: Colors.white,
        onPressed: () async {
          final ok = await showDialog<bool>(context: context, builder: (_) => const _NewCatalogDialog());
          if (ok == true) ref.invalidate(_catalogProvider);
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ürün ekle'),
      ),
      body: c.when(
        loading: () => const Loading(),
        error: (e, _) => ErrorPanel(e, onRetry: () => ref.invalidate(_catalogProvider)),
        data: (items) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
          EtkenCard(
            color: EtkenColors.commercialTint,
            child: Text('Burada eklediğiniz ürünler reçete kontrolünde "TİCARİ · KLİNİK ÖNERİ DEĞİLDİR" etiketiyle ayrı bir bölümde gösterilir ve klinik bulguları etkilemez.',
                style: bodyStyle(14)),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const EmptyPanel(title: 'Katalog boş', body: 'Örn. antibiyotik reçetelerinde (ATC J01) önermek istediğiniz bir probiyotiği ekleyin.')
          else
            EtkenCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final (i, x) in items.indexed)
                  Container(
                    decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: EtkenColors.lineSoft))),
                    child: ListTile(
                      title: Text(x['name'] as String, style: bodyStyle(15, weight: FontWeight.w700)),
                      subtitle: Text(
                        '${x['triggerType'] == 'atc' ? 'ATC' : 'Etken madde'}: ${x['triggerValue']}'
                        '${(x['note'] as String?)?.isNotEmpty == true ? ' · ${x['note']}' : ''}',
                        style: bodyStyle(13, color: EtkenColors.muted),
                      ),
                      trailing: IconButton(
                        tooltip: 'Sil',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          await ref.read(apiProvider).send('DELETE', '/catalog/${x['id']}');
                          ref.invalidate(_catalogProvider);
                        },
                      ),
                    ),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _NewCatalogDialog extends ConsumerStatefulWidget {
  const _NewCatalogDialog();
  @override
  ConsumerState<_NewCatalogDialog> createState() => _NewCatalogDialogState();
}

class _NewCatalogDialogState extends ConsumerState<_NewCatalogDialog> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  final _value = TextEditingController();
  String _type = 'atc';
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _note, _value]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await ref.read(apiProvider).post('/catalog', {
        'name': _name.text.trim(),
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'triggerType': _type,
        'triggerValue': _value.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Destekleyici ürün'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Ürün adı')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _type,
              style: bodyStyle(16, color: EtkenColors.ink),
              decoration: const InputDecoration(labelText: 'Ne zaman önerilsin?'),
              items: const [
                DropdownMenuItem(value: 'atc', child: Text('ATC grubu ile başlayınca')),
                DropdownMenuItem(value: 'ingredient', child: Text('Etken madde içerince')),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _value,
              textCapitalization: _type == 'atc' ? TextCapitalization.characters : TextCapitalization.none,
              decoration: InputDecoration(labelText: _type == 'atc' ? 'ATC öneki (örn. J01)' : 'Etken madde (örn. amoksisilin)'),
            ),
            const SizedBox(height: 10),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)')),
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: bodyStyle(14, color: EtkenColors.riskCritical))],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(onPressed: _save, child: const Text('Ekle')),
        ],
      );
}
