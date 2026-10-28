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
      final session = await AuthApi.login(localPhone(_phone.text), _password.text);
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
    // With the keyboard up the header compacts, so the form and Sign in stay
    // on screen. The header lives in one slot either way: the fields below
    // must keep their place in the tree or they lose focus and text.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    const muted = Color(0xFF9AA6B8);
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: nightInk,
        body: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: _RadiusRings())),
          SafeArea(
            bottom: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(28, typing ? 12 : 40, 28, typing ? 14 : 28),
                  child: typing
                      ? const Row(children: [RadianMark(size: 36, ground: nightInk), SizedBox(width: 10), RadianWordmark(size: 26)])
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const RadianMark(size: 72, ground: nightInk),
                          const SizedBox(height: 16),
                          Text('Ready to drive?', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 32, letterSpacing: -1)),
                          const SizedBox(height: 8),
                          Text('Sign in with the phone number your dispatcher registered.', style: theme.textTheme.bodyLarge?.copyWith(color: muted, height: 1.45)),
                        ]),
                ),
              ),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF131C2E),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(top: BorderSide(color: Color(0xFF263247))),
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 26, 24, 24 + MediaQuery.paddingOf(context).bottom),
                    child: Form(
                      key: _form,
                      child: AutofillGroup(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          TextFormField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            autofillHints: const [AutofillHints.telephoneNumber],
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(fontFamily: monoFamily, fontSize: 17),
                            decoration: const InputDecoration(
                              labelText: 'Phone number',
                              prefixIcon: Padding(
                                padding: EdgeInsets.only(left: 16, right: 10),
                                child: Text('+233', style: TextStyle(fontFamily: monoFamily, fontSize: 16, color: Color(0xFFF3F6FA))),
                              ),
                              prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                            ),
                            validator: (v) => localPhone(v ?? '').length < 10 ? 'Enter your phone number' : null,
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
                              suffixIcon: IconButton(
                                tooltip: _obscure ? 'Show password' : 'Hide password',
                                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                : const Text('Sign in'),
                          ),
                          if (!typing) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Location is used only while you are on shift',
                              textAlign: TextAlign.center,
                              style: mono(theme.textTheme.bodySmall).copyWith(color: muted),
                            ),
                          ],
                        ]),
                      ),
                    ),
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

/// Local Ghana number from what the driver typed: "24 000 0001", "0240000001"
/// and "+233 24 000 0001" all become "0240000001".
String localPhone(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('233') && digits.length == 12) digits = digits.substring(3);
  if (digits.isNotEmpty && !digits.startsWith('0')) digits = '0$digits';
  return digits;
}

/// Faint concentric search radii behind the header.
class _RadiusRings extends CustomPainter {
  const _RadiusRings();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.2, size.height * 0.36);
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
        center,
        size.width * (0.28 + 0.2 * i),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = signalBlue.withValues(alpha: 0.12 - 0.025 * i),
      );
    }
  }

  @override
  bool shouldRepaint(_RadiusRings old) => false;
}
