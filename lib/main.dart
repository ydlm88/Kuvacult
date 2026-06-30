// main.dart — App entry point: configures image cache and system UI, then routes to MainShell or OnboardingScreen based on stored JWT.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'theme.dart';
import 'screens/onboarding.dart';
import 'screens/main_shell.dart';
import 'widgets/kuvacult_loader.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep more decoded images in RAM so carousels and profile banners don't
  // re-decode from disk on every scroll. 150 MB is reasonable on modern devices;
  // cached_network_image handles the on-disk layer separately.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 150 * 1024 * 1024;
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0806),
  ));
  runApp(const KuvacultApp());
}

class KuvacultApp extends StatelessWidget {
  const KuvacultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Kuvacult',
        debugShowCheckedModeBanner: false,
        theme: MT.theme,
        home: const _AppRouter(),
      ),
    );
  }
}

// Checks for a stored session before showing onboarding.
// If tokens are found and the refresh succeeds, goes directly to MainShell.
class _AppRouter extends StatefulWidget {
  const _AppRouter();
  @override
  State<_AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<_AppRouter> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Future<void> _restore() async {
    await context.read<AppState>().tryRestoreSession();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: MC.bg0,
        body: Center(child: KuvacultLoader()),
      );
    }
    return context.read<AppState>().isLoggedIn
        ? const MainShell()
        : const OnboardingScreen();
  }
}
