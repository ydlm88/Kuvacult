import 'package:flutter/material.dart';
import '../theme.dart';

class ServerDownScreen extends StatelessWidget {
  const ServerDownScreen({super.key});

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
            ],
          ),
        ),
      ),
    );
  }
}
