// auth.dart — Sign-in, registration, and email-verification screens for Kuvacult.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../app_state.dart';
import '../services/auth_service.dart';
import 'main_shell.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isRegister = false;
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _nameCtrl     = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _rememberMe = true;
  String? _error;

  // Non-null value means auth succeeded but email is unverified; drives the check-email view.
  String? _pendingEmail;
  bool _resending = false;
  bool _resent    = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final state = context.read<AppState>();
    setState(() { _loading = true; _error = null; });
    try {
      if (_isRegister) {
        final name = _nameCtrl.text.trim();
        await state.register(
          _usernameCtrl.text.trim(),
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
          name.isEmpty ? _usernameCtrl.text.trim() : name,
        );
      } else {
        await state.login(_emailCtrl.text.trim(), _passwordCtrl.text, rememberMe: _rememberMe);
      }
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainShell()),
          (_) => false,
        );
      }
    } on RegistrationPendingException {
      setState(() => _pendingEmail = _emailCtrl.text.trim());
    } on EmailNotVerifiedException {
      setState(() {
        _pendingEmail = _emailCtrl.text.trim();
        _error = null;
      });
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var sending = false;
        var sent    = false;
        return StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            backgroundColor: MC.bg1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              'Reset password',
              style: TextStyle(color: MC.ink, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!sent) ...[
                  const Text(
                    "Enter your email and we'll send a reset link.",
                    style: TextStyle(color: MC.mute, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    style: const TextStyle(color: MC.ink, fontSize: 15),
                    decoration: _inputDecoration(),
                  ),
                ] else
                  const Text(
                    "If that email is registered you'll receive a reset link. Check your inbox.",
                    style: TextStyle(color: MC.mute, fontSize: 13, height: 1.5),
                  ),
              ],
            ),
            actions: [
              if (!sent)
                TextButton(
                  onPressed: sending ? null : () async {
                    final email = emailCtrl.text.trim();
                    if (email.isEmpty) return;
                    setDialog(() => sending = true);
                    await context.read<AppState>().forgotPassword(email);
                    if (ctx.mounted) setDialog(() { sending = false; sent = true; });
                  },
                  child: sending
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: MC.accent1),
                        )
                      : const Text('Send link',
                          style: TextStyle(color: MC.accent1, fontWeight: FontWeight.w600)),
                )
              else
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done',
                      style: TextStyle(color: MC.accent1, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        );
      },
    );

    emailCtrl.dispose();
  }

  Future<void> _resend() async {
    if (_pendingEmail == null || _resending) return;
    setState(() { _resending = true; _resent = false; });
    await context.read<AppState>().resendVerification(_pendingEmail!);
    if (mounted) setState(() { _resending = false; _resent = true; });
  }

  void _backToSignIn() {
    setState(() {
      _pendingEmail = null;
      _resent       = false;
      _isRegister   = false;
      _error        = null;
    });
  }

  void _continueAsGuest() {
    context.read<AppState>().loginAsGuest();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainShell()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingEmail != null) return _buildCheckEmailView();

    return Scaffold(
      backgroundColor: MC.bg0,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: MC.ink, size: 20),
              ),
              const SizedBox(height: 32),

              Text('Welcome to', style: MT.mono(size: 11, letterSpacing: 2, color: MC.mute)),
              const SizedBox(height: 6),
              Text('Kuvacult', style: MT.display(size: 40)),
              const SizedBox(height: 32),

              Row(
                children: [
                  _toggleTab('Sign In',       !_isRegister),
                  const SizedBox(width: 8),
                  _toggleTab('Create Account', _isRegister),
                ],
              ),
              const SizedBox(height: 28),

              if (_isRegister) ...[
                _field('Display name', _nameCtrl),
                const SizedBox(height: 12),
                _field('Username', _usernameCtrl),
                const SizedBox(height: 12),
              ],

              _field('Email', _emailCtrl, type: TextInputType.emailAddress),
              const SizedBox(height: 12),
              _passwordField(),
              const SizedBox(height: 8),

              if (!_isRegister) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _forgotPassword,
                    child: Text(
                      'Forgot password?',
                      style: MT.mono(size: 11, letterSpacing: 0.5, color: MC.accent1),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _rememberMeRow(),
                const SizedBox(height: 16),
              ] else
                const SizedBox(height: 12),

              GestureDetector(
                onTap: _loading ? null : _submit,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [MC.accent1, MC.accent2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(color: Color(0x44E8A93A), blurRadius: 20, offset: Offset(0, 4)),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: _loading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(color: MC.accentInk, strokeWidth: 2),
                        )
                      : Text(
                          _isRegister ? 'Create Account' : 'Sign In',
                          style: const TextStyle(
                            color: MC.accentInk,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckEmailView() {
    return Scaffold(
      backgroundColor: MC.bg0,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _backToSignIn,
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: MC.ink, size: 20),
              ),
              const SizedBox(height: 48),

              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: MC.accent1.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_unread_outlined,
                    color: MC.accent1, size: 32),
              ),
              const SizedBox(height: 24),

              Text('Check your email', style: MT.display(size: 28)),
              const SizedBox(height: 10),
              Text(
                'We sent a verification link to\n$_pendingEmail',
                style: const TextStyle(color: MC.mute, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 8),
              const Text(
                'Click the link in the email to activate your account, then sign in.',
                style: TextStyle(color: MC.dim, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 40),

              GestureDetector(
                onTap: _resend,
                child: Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _resent ? MC.accent1 : MC.line,
                      width: _resent ? 1 : 0.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: _resending
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: MC.accent1, strokeWidth: 2))
                      : Text(
                          _resent ? 'Email sent!' : 'Resend verification email',
                          style: TextStyle(
                              color: _resent ? MC.accent1 : MC.mute,
                              fontSize: 14),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              Center(
                child: GestureDetector(
                  onTap: _backToSignIn,
                  child: Text(
                    'Back to Sign In',
                    style: MT.mono(size: 11, letterSpacing: 1, color: MC.accent1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rememberMeRow() => GestureDetector(
    onTap: () => setState(() => _rememberMe = !_rememberMe),
    behavior: HitTestBehavior.opaque,
    child: Row(
      children: [
        SizedBox(
          width: 20, height: 20,
          child: Checkbox(
            value: _rememberMe,
            onChanged: (v) => setState(() => _rememberMe = v ?? true),
            activeColor: MC.accent1,
            checkColor: MC.bg0,
            side: const BorderSide(color: MC.mute, width: 0.8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 10),
        const Text('Remember me', style: TextStyle(color: MC.mute, fontSize: 13)),
      ],
    ),
  );

  Widget _toggleTab(String label, bool active) => GestureDetector(
    onTap: () {
      if (_isRegister == (label == 'Create Account')) return;
      setState(() { _isRegister = label == 'Create Account'; _error = null; });
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: active ? MC.accent1.withAlpha(38) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? MC.accent1 : MC.line, width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? MC.accent1 : MC.mute,
          fontSize: 14,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    ),
  );

  Widget _field(
    String label,
    TextEditingController ctrl, {
    TextInputType? type,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: MC.mute, fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            keyboardType: type,
            style: const TextStyle(color: MC.ink, fontSize: 15),
            decoration: _inputDecoration(),
          ),
        ],
      );

  Widget _passwordField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Password', style: TextStyle(color: MC.mute, fontSize: 12)),
      const SizedBox(height: 6),
      TextField(
        controller: _passwordCtrl,
        obscureText: _obscure,
        style: const TextStyle(color: MC.ink, fontSize: 15),
        decoration: _inputDecoration().copyWith(
          suffixIcon: IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: MC.mute,
              size: 18,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
    ],
  );

  InputDecoration _inputDecoration() => InputDecoration(
    filled: true,
    fillColor: MC.bg1,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: MC.line, width: 0.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: MC.line, width: 0.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: MC.accent1, width: 1),
    ),
  );
}
