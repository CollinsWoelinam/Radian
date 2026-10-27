import 'package:flutter/material.dart';

import '../auth/session.dart';
import 'theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignedIn});

  final void Function(Session) onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await AuthApi.login(_phone.text, _password.text);
      await SessionStore.save(session);
      widget.onSignedIn(session);
    } on LoginException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The entry screen is always on Night Ink, like the splash it follows.
    final theme = buildTheme(Brightness.dark);
    // With the keyboard up, shrink the brand so Sign in stays on screen.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: nightInk,
        body: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _RadiusRings())),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: _form,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (typing)
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  RadianMark(size: 44, ground: nightInk),
                                  SizedBox(width: 10),
                                  RadianWordmark(size: 30),
                                ],
                              )
                            else ...[
                              Text(
                                'DRIVER',
                                textAlign: TextAlign.center,
                                style: mono(
                                  theme.textTheme.labelMedium,
                                ).copyWith(letterSpacing: 3.6, color: theme.colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 28),
                              const Center(child: RadianMark(size: 112, ground: nightInk)),
                              const SizedBox(height: 14),
                              const Center(child: RadianWordmark(size: 44)),
                              const SizedBox(height: 10),
                              Text(
                                'Your shift, tracked and dispatched.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                            SizedBox(height: typing ? 20 : 36),
                            TextFormField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              autofillHints: const [AutofillHints.telephoneNumber],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone_outlined)),
                              validator: (v) => (v ?? '').trim().length < 9 ? 'Enter your phone number' : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _password,
                              obscureText: _obscure,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _obscure ? 'Show password' : 'Hide password',
                                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                            ],
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                    )
                                  : const Text('Sign in'),
                            ),
                            if (!typing) ...[
                              const SizedBox(height: 14),
                              Text(
                                'Location is used only while you are on shift',
                                textAlign: TextAlign.center,
                                style: mono(theme.textTheme.bodySmall).copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faint concentric search radii behind the sign-in form.
class _RadiusRings extends CustomPainter {
  const _RadiusRings();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.29, size.height * 0.5);
    for (var i = 0; i < 5; i++) {
      final r = size.width * (0.3 + 0.24 * i);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = signalBlue.withValues(alpha: 0.1 - 0.015 * i),
      );
    }
  }

  @override
  bool shouldRepaint(_RadiusRings old) => false;
}
