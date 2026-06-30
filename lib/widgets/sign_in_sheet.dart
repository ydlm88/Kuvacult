//Most of these features are removed for now.
// sign_in_sheet.dart — Modal bottom sheet prompting guest users to sign in or create an account.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../screens/auth.dart';

/// Call this anywhere a guest taps a feature that requires an account. 
void showSignInSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: MC.bg1,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: MC.dim, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 24),
          const Icon(Icons.lock_outline_rounded, color: MC.accent1, size: 32),
          const SizedBox(height: 16),
          Text('Sign in required',
              style: MT.display(size: 22), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
            'Create an account or sign in to use this feature.',
            style: TextStyle(color: MC.mute, fontSize: 14, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AuthScreen()),
              );
            },
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [MC.accent1, MC.accent2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Sign in / Create account',
                style: TextStyle(
                    color: MC.accentInk,
                    fontWeight: FontWeight.w600,
                    fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
