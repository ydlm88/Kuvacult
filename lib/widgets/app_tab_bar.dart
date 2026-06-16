import 'package:flutter/material.dart';
import '../theme.dart';

class AppTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 28,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xB8141010),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: MC.line, width: 0.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 32,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _tab(0, _TabIcon.home),
            _tab(1, _TabIcon.reviews),
            _centerTab(),
            _tab(3, _TabIcon.ticket),
            _tab(4, _TabIcon.person),
          ],
        ),
      ),
    );
  }

  Widget _tab(int idx, _TabIcon icon) {
    final isActive = currentIndex == idx;
    return GestureDetector(
      onTap: () => onTap(idx),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: _buildIcon(icon, isActive ? MC.accent1 : MC.mute),
        ),
      ),
    );
  }

  Widget _centerTab() {
    final isActive = currentIndex == 2;
    return GestureDetector(
      onTap: () => onTap(2),
      child: Container(
        width: 52,
        height: 52,
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [MC.accent1, MC.accent2],
          ),
          boxShadow: [
            BoxShadow(
              color: MC.accent2.withAlpha(85),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          Icons.add_rounded,
          color: isActive ? MC.accentInk.withAlpha(220) : MC.accentInk,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildIcon(_TabIcon icon, Color color) {
    switch (icon) {
      case _TabIcon.home:
        return Icon(Icons.home_outlined, color: color, size: 22);
      case _TabIcon.reviews:
        return Icon(Icons.rate_review_outlined, color: color, size: 22);
      case _TabIcon.ticket:
        return Icon(Icons.confirmation_number_outlined, color: color, size: 22);
      case _TabIcon.person:
        return Icon(Icons.person_outline_rounded, color: color, size: 22);
    }
  }
}

enum _TabIcon { home, reviews, ticket, person }
