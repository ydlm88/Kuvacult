import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../app_state.dart';
import 'main_shell.dart';

// AuthScreen — single entry point for both sign-up and login.
// Uses Auth0 Universal Login (browser-based) so we never handle credentials
// ourselves. The Auth0 hosted UI covers email/password, Google, GitHub, etc.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.bg0,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Back ──────────────────────────────────────────────────────────
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: MC.ink, size: 20),
              ),
              const Spacer(),

              // ── Headline ──────────────────────────────────────────────────────
              Text('Welcome to', style: MT.mono(size: 11, letterSpacing: 2, color: MC.mute)),
              const SizedBox(height: 6),
              Text('Marquee', style: MT.display(size: 40)),
              const SizedBox(height: 12),
              const Text(
                'Sign in or create an account to start\nyour shared watchlist.',
                style: TextStyle(color: MC.mute, fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 48),

              // ── Auth0 Universal Login button ───────────────────────────────────
              // Tapping this opens Auth0's hosted login page in the system browser.
              // Auth0 handles sign-up, login, password reset, and social providers.
              // TODO(auth): Configure social connections (Google, GitHub) in Auth0 Dashboard
              // → Authentication → Social → Enable the providers you want.
              GestureDetector(
                onTap: _loading ? null : _signInWithAuth0,
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
                      BoxShadow(
                        color: Color(0x44E8A93A),
                        blurRadius: 20,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: MC.accentInk, strokeWidth: 2),
                        )
                      : const Text(
                          'Sign in / Create account',
                          style: TextStyle(
                            color: MC.accentInk,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                ),
              ),

              // ── Error message ─────────────────────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 20),

              // ── Guest divider ─────────────────────────────────────────────────
              Center(
                child: Text(
                  'OR CONTINUE AS GUEST',
                  style: MT.mono(size: 10, letterSpacing: 2),
                ),
              ),
              const SizedBox(height: 12),

              // ── Guest button ──────────────────────────────────────────────────
              // Guest profile: no account, no friends, empty watchlist.
              // Useful for demoing the UI before committing to sign-up.
              GestureDetector(
                onTap: _continueAsGuest,
                child: Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MC.line, width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Browse as guest',
                    style: TextStyle(color: MC.mute, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // Triggers Auth0 Universal Login browser flow via AppState.login().
  Future<void> _signInWithAuth0() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().login();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainShell()),
          (_) => false,
        );
      }
    } catch (e) {
      // User cancelled the browser or an Auth0 error occurred
      setState(() => _error = 'Sign in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Sets a guest UserAccount with empty state and navigates to the main shell.
  void _continueAsGuest() {
    context.read<AppState>().loginAsGuest();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainShell()),
      (_) => false,
    );
  }
}
