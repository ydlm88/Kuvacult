import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/app_tab_bar.dart';
import 'community_reviews.dart';
import 'watchlists.dart';
import 'search.dart';
import 'veto.dart';
import 'profile.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const List<Widget> _screens = [
    WatchlistsScreen(),
    CommunityReviewsScreen(),
    SearchScreen(),
    VetoScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final invite = context.select<AppState, VetoInvite?>((s) => s.pendingVetoInvite);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0806),
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: _screens),
          AppTabBar(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
          ),
          if (invite != null)
            _VetoInviteBanner(
              invite: invite,
              onAccept: () {
                context.read<AppState>().dismissVetoInvite();
                setState(() => _currentIndex = 3);
              },
              onDismiss: () => context.read<AppState>().dismissVetoInvite(),
            ),
        ],
      ),
    );
  }
}

class _VetoInviteBanner extends StatelessWidget {
  final VetoInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const _VetoInviteBanner({
    required this.invite,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: MC.bg1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MC.accent1.withAlpha(120), width: 0.5),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: MC.accent1.withAlpha(30),
                  shape: BoxShape.circle,
                  border: Border.all(color: MC.accent1, width: 0.5),
                ),
                child: const Icon(Icons.how_to_vote_outlined,
                    color: MC.accent1, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${invite.fromName} started a veto',
                      style: const TextStyle(
                          color: MC.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.2),
                    ),
                    Text(
                      invite.watchlistName,
                      style: MT.mono(size: 10, letterSpacing: 1, color: MC.mute),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onAccept,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: MC.accent1,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Join',
                      style: TextStyle(
                          color: MC.accentInk,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onDismiss,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, color: MC.dim, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
