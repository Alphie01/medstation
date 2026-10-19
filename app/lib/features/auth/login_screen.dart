import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'E-posta ve parola gerekli');
      return;
    }
    setState(() => (_busy = true, _error = null));
    try {
      await ref.read(authProvider.notifier).login(_email.text.trim(), _pass.text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final msg = ref.watch(authProvider).message;
    return Scaffold(
      body: ListView(children: [
        HeroHeader(
          decor: true,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 84),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: EtkenColors.coral, borderRadius: BorderRadius.circular(11)),
                child: Text('m', style: displayStyle(21, weight: FontWeight.w800, color: EtkenColors.ink, height: 1)),
              ),
              const SizedBox(width: 10),
              Text('medstation', style: displayStyle(22, color: Colors.white)),
            ]),
            const SizedBox(height: 60),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 215),
              child: Text('Eczacının ilaç asistanı.', style: displayStyle(40, weight: FontWeight.w800, color: Colors.white, height: 0.98)),
            ),
          ]),
        ),
        Transform.translate(
          offset: const Offset(0, -52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: EtkenColors.surface,
                borderRadius: BorderRadius.circular(EtkenRadius.card),
                boxShadow: [BoxShadow(color: EtkenColors.navy.withValues(alpha: 0.2), blurRadius: 44, offset: const Offset(0, 22))],
              ),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (msg != null) ...[Text(msg, style: bodyStyle(14, color: EtkenColors.riskMajor)), const SizedBox(height: 10)],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'E-posta'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: 'Parola'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Semantics(liveRegion: true, child: Text(_error!, style: bodyStyle(14, color: EtkenColors.riskCritical))),
                  ],
                  const SizedBox(height: 16),
                  CtaButton(label: 'Giriş yap', loading: _busy, onPressed: _submit),
                ]),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text('Hesaplar eczane yöneticisi tarafından oluşturulur.', textAlign: TextAlign.center, style: bodyStyle(13, color: EtkenColors.muted)),
        ),
      ]),
    );
  }
}

class LockScreen extends ConsumerWidget {
  const LockScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        backgroundColor: EtkenColors.navy,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(),
              const Icon(Icons.lock_outline_rounded, size: 56, color: Colors.white),
              const SizedBox(height: 16),
              Text('MedStation kilitli', style: displayStyle(30, weight: FontWeight.w800, color: Colors.white)),
              const Spacer(),
              CtaButton(coral: true, label: 'Kilidi aç', onPressed: () => ref.read(authProvider.notifier).unlock()),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => ref.read(authProvider.notifier).logout(),
                child: Text('Farklı hesapla giriş yap', style: bodyStyle(15, color: Colors.white)),
              ),
            ]),
          ),
        ),
      );
}
