import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'theme.dart';
import 'screens/onboarding.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0806),
  ));
  runApp(const MarqueeApp());
}

class MarqueeApp extends StatelessWidget {
  const MarqueeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Marquee',
        debugShowCheckedModeBanner: false,
        theme: MT.theme,
        home: const OnboardingScreen(),
      ),
    );
  }
}
