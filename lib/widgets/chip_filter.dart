import 'package:flutter/material.dart';
import '../theme.dart';

class ChipFilter extends StatelessWidget {
  final List<String> items;
  final String active;
  final ValueChanged<String> onSelect;

  const ChipFilter({
    super.key,
    required this.items,
    required this.active,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          final isActive = active == item;
          return GestureDetector(
            onTap: () => onSelect(item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isActive ? MC.accent1 : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? MC.accent1 : MC.line,
                  width: 0.5,
                ),
              ),
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isActive ? MC.accentInk : MC.ink,
                  letterSpacing: -0.1,
                  height: 1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
