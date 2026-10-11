import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../services/api_service.dart';
import '../theme.dart';

class ServerDownScreen extends StatefulWidget {
  const ServerDownScreen({super.key});

  @override
  State<ServerDownScreen> createState() => _ServerDownScreenState();
}

class _ServerDownScreenState extends State<ServerDownScreen> {
  bool _retrying = false;
  bool _failed = false;

  Future<void> _retry() async {
    setState(() {
      _retrying = true;
      _failed = false;
    });
    final up = await ApiService.isServerUp();
    if (!mounted) return;
    if (up) {
      final appState = context.read<AppState>();
      appState.clearServerDown();
      await appState.tryRestoreSession();
    } else {
      setState(() {
        _retrying = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.bg0,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/sus_sun.png',
                width: 240,
                height: 240,
              ),
              const SizedBox(height: 36),
              Text(
                'Something went wrong with the ritual..',
                style: MT.display(size: 26, italic: true, height: 1.2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              const Text(
                'Server is down please check again later',
                style: TextStyle(
                  color: MC.mute,
                  fontSize: 14,
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_retrying)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MC.accent1,
                  ),
                )
              else
                TextButton(
                  onPressed: _retry,
                  style: TextButton.styleFrom(
                    foregroundColor: MC.accent1,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: MC.accent1, width: 1),
                    ),
                  ),
                  child: const Text('Try Again'),
                ),
              if (_failed) ...[
                const SizedBox(height: 12),
                const Text(
                  'Still down. Try again in a moment.',
                  style: TextStyle(color: MC.mute, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
