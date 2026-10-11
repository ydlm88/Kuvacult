// main_shell.dart — Root scaffold after login: owns the bottom tab bar and overlays veto invite banners.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/app_tab_bar.dart';
import '../services/update_service.dart';
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
  String? _updateTag;

  @override
  void initState() {
    super.initState();
    UpdateService.checkForUpdate().then((tag) {
      if (tag != null && mounted) setState(() => _updateTag = tag);
    });
  }

  void _showRitualInbox(BuildContext context, List<SeanceSession> sessions, List<VetoInvite> vetoInvites) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _RitualInboxSheet(
        sessions: sessions,
        vetoInvites: vetoInvites,
        onJoinSeance: (session) {
          Navigator.of(ctx).pop();
          context.read<AppState>().acceptSeanceBannerFor(session);
          setState(() => _currentIndex = 3);
        },
        onJoinVeto: (invite) {
          Navigator.of(ctx).pop();
          context.read<AppState>().acceptVetoInviteFor(invite.watchlistId);
          setState(() => _currentIndex = 3);
        },
        onDismissVeto: (invite) {
          context.read<AppState>().dismissVetoInviteFor(invite.watchlistId);
        },
      ),
    );
  }

  static const List<Widget> _screens = [
    WatchlistsScreen(),
    CommunityReviewsScreen(),
    SearchScreen(),
    VetoScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final seanceNotif  = context.select<AppState, SeanceSession?>((s) => s.pendingSeanceBanner);
    final availableSeances = context.select<AppState, List<SeanceSession>>((s) => s.availableSeances);
    final vetoInvite   = context.select<AppState, VetoInvite?>((s) => s.pendingVetoInvite);
    final vetoInvites  = context.select<AppState, List<VetoInvite>>((s) => s.pendingVetoInvites);
    final ritualInboxCount = context.select<AppState, int>((s) => s.ritualInboxCount);
    final wlInvite     = context.select<AppState, WatchlistInvite?>((s) => s.pendingWatchlistInviteBanner);
    final friendReq    = context.select<AppState, FriendRequest?>((s) => s.pendingFriendRequestBanner);
    final activityNotif = context.select<AppState, AppNotification?>((s) => s.activeActivityBanner);

    // Priority: séance > veto > watchlist invite > friend request > activity (auto-dismiss).
    // On the Ritual tab: séance invites always show (the card can't show who invited you
    // unless it's already active). Non-séance banners are suppressed to keep focus.
    final bool onRitual = _currentIndex == 3;
    final Widget? activeBanner = seanceNotif != null && !onRitual
            ? _SeanceBanner(
                session: seanceNotif,
                onJoin: () {
                  context.read<AppState>().acceptSeanceBanner();
                  setState(() => _currentIndex = 3);
                },
                onDismiss: () => context.read<AppState>().dismissSeanceBannerAndStore(),
              )
            : onRitual
                ? null   // suppress non-séance banners on Ritual tab
                : vetoInvite != null
                    ? _VetoInviteBanner(
                        invite: vetoInvite,
                        onAccept: () {
                          context.read<AppState>().acceptVetoInvite();
                          setState(() => _currentIndex = 3);
                        },
                        onDismiss: () => context.read<AppState>().dismissVetoInvite(),
                      )
                    : wlInvite != null
                        ? _WatchlistInviteBanner(
                            invite: wlInvite,
                            onAccept: () => context.read<AppState>()
                                .acceptWatchlistInvite(wlInvite.watchlistId, wlInvite.id),
                            onDismiss: () => context.read<AppState>()
                                .dismissWatchlistInviteBanner(wlInvite.id),
                          )
                        : friendReq != null
                            ? _FriendRequestBanner(
                                request: friendReq,
                                onAccept: () =>
                                    context.read<AppState>().acceptFriendRequest(friendReq.id),
                                onDismiss: () => context.read<AppState>()
                                    .dismissFriendRequestBanner(friendReq.id),
                              )
                            : activityNotif != null
                                ? _ActivityBanner(
                                    notif: activityNotif,
                                    onDismiss: () =>
                                        context.read<AppState>().dismissActivityBanner(),
                                  )
                                : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0806),
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: _screens),
          AppTabBar(
            currentIndex: _currentIndex,
            onTap: (i) {
              setState(() => _currentIndex = i);
              if (i == 3) {
                context.read<AppState>().refreshAvailableSeances();
                context.read<AppState>().refreshVetoInvites();
              }
            },
          ),
          if (activeBanner != null) activeBanner,
          if (onRitual && ritualInboxCount > 0)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: () => _showRitualInbox(context, availableSeances, vetoInvites),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1210),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE8A13C).withAlpha(140)),
                          boxShadow: const [
                            BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 3)),
                          ],
                        ),
                        child: const Icon(Icons.notifications_outlined, size: 18, color: Color(0xFFE8A13C)),
                      ),
                      Positioned(
                        top: -3,
                        right: -3,
                        child: Container(
                          height: 16,
                          constraints: const BoxConstraints(minWidth: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4ADE80),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            ritualInboxCount > 9 ? '9+' : '$ritualInboxCount',
                            style: TextStyle(
                              fontFamily: GoogleFonts.martianMono().fontFamily,
                              fontSize: 8,
                              color: const Color(0xFF0A0A0A),
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_updateTag != null)
            _UpdateBanner(
              tag: _updateTag!,
              onDismiss: () => setState(() => _updateTag = null),
            ),
        ],
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  final String tag;
  final VoidCallback onDismiss;

  const _UpdateBanner({required this.tag, required this.onDismiss});

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
              BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 6)),
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
                child: const Icon(Icons.system_update_outlined, color: MC.accent1, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Update available — $tag',
                        style: const TextStyle(
                            color: MC.ink, fontSize: 13, fontWeight: FontWeight.w600, height: 1.2)),
                    Text('Tap to download', style: MT.mono(size: 10, letterSpacing: 1, color: MC.mute)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse('https://github.com/ydlm88/Kuvacult/releases/latest'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: MC.accent1,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Download',
                      style: TextStyle(
                          color: MC.accentInk, fontSize: 12, fontWeight: FontWeight.w600)),
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

class _FriendRequestBanner extends StatelessWidget {
  final FriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const _FriendRequestBanner({
    required this.request,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final name = request.fromDisplayName?.isNotEmpty == true
        ? request.fromDisplayName!
        : (request.fromUsername ?? 'Someone');
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
              BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 6)),
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
                child: const Icon(Icons.person_add_outlined, color: MC.accent1, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: MC.ink, fontSize: 13, fontWeight: FontWeight.w600, height: 1.2)),
                    Text('wants to be friends',
                        style: MT.mono(size: 10, letterSpacing: 1, color: MC.mute)),
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
                  child: Text('Accept',
                      style: TextStyle(
                          color: MC.accentInk, fontSize: 12, fontWeight: FontWeight.w600)),
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

class _ActivityBanner extends StatelessWidget {
  final AppNotification notif;
  final VoidCallback onDismiss;

  const _ActivityBanner({required this.notif, required this.onDismiss});

  String _buildText() {
    final who = notif.fromName ?? 'Someone';
    switch (notif.type) {
      case NotifType.likedReview:
        return '$who liked your review${notif.movieTitle != null ? ' of ${notif.movieTitle}' : ''}';
      case NotifType.likedWatchlist:
        return '$who liked your watchlist${notif.watchlistName != null ? ' "${notif.watchlistName}"' : ''}';
      case NotifType.followed:
        return '$who followed you';
      default:
        return '$who sent you a notification';
    }
  }

  IconData _icon() {
    switch (notif.type) {
      case NotifType.likedReview:
      case NotifType.likedWatchlist:
        return Icons.favorite_rounded;
      case NotifType.followed:
        return Icons.person_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(
            color: MC.bg1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MC.line, width: 0.5),
            boxShadow: const [
              BoxShadow(color: Color(0x44000000), blurRadius: 20, offset: Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: const Color(0x22E05A7A),
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon(), color: const Color(0xFFE05A7A), size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _buildText(),
                  style: const TextStyle(color: MC.ink, fontSize: 13, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDismiss,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, color: MC.dim, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WatchlistInviteBanner extends StatelessWidget {
  final WatchlistInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const _WatchlistInviteBanner({
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
              BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 6)),
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
                child: const Icon(Icons.remove_red_eye_outlined, color: MC.accent1, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${invite.inviterName} invited you to join',
                      style: const TextStyle(
                          color: MC.ink, fontSize: 13, fontWeight: FontWeight.w600, height: 1.2),
                    ),
                    Text(invite.watchlistName,
                        style: MT.mono(size: 10, letterSpacing: 1, color: MC.mute)),
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
                          color: MC.accentInk, fontSize: 12, fontWeight: FontWeight.w600)),
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

// ── Ritual Inbox bottom sheet — lists all pending séances and veto invites ──
class _RitualInboxSheet extends StatelessWidget {
  final List<SeanceSession> sessions;
  final List<VetoInvite> vetoInvites;
  final void Function(SeanceSession) onJoinSeance;
  final void Function(VetoInvite) onJoinVeto;
  final void Function(VetoInvite) onDismissVeto;

  const _RitualInboxSheet({
    required this.sessions,
    required this.vetoInvites,
    required this.onJoinSeance,
    required this.onJoinVeto,
    required this.onDismissVeto,
  });

  Widget _seanceRow(SeanceSession s) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1210),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33E8A13C)),
      ),
      child: Row(
        children: [
          const Text('🕯️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.hostName,
                  style: const TextStyle(
                    color: Color(0xFFF3E4CF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                Text(
                  'séance is open',
                  style: MT.mono(size: 10, letterSpacing: 0.6, color: MC.mute),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onJoinSeance(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: MC.accent1,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                'JOIN',
                style: TextStyle(
                  color: MC.accentInk,
                  fontFamily: GoogleFonts.martianMono().fontFamily,
                  fontSize: 10,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _vetoRow(VetoInvite v) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF121A18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x2294C4A1)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Color(0x1594C4A1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.how_to_vote_outlined, size: 16, color: Color(0xFF94C4A1)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.fromName,
                  style: const TextStyle(
                    color: Color(0xFFF3E4CF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                Text(
                  'started a veto · ${v.watchlistName}',
                  style: MT.mono(size: 10, letterSpacing: 0.6, color: MC.mute),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => onJoinVeto(v),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF94C4A1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                'JOIN',
                style: TextStyle(
                  color: const Color(0xFF0D1A14),
                  fontFamily: GoogleFonts.martianMono().fontFamily,
                  fontSize: 10,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => onDismissVeto(v),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, color: MC.dim, size: 16),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121010),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: Color(0x47E8A13C)),
          left: BorderSide(color: Color(0x47E8A13C)),
          right: BorderSide(color: Color(0x47E8A13C)),
        ),
      ),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0x33F3E4CF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.notifications_outlined, size: 16, color: Color(0xFFE8A13C)),
                    const SizedBox(width: 8),
                    Text(
                      'RITUAL INBOX',
                      style: MT.mono(size: 10, letterSpacing: 1.8, color: const Color(0xFFE8A13C)),
                    ),
                    const Spacer(),
                    Text(
                      '${sessions.length + vetoInvites.length}',
                      style: MT.mono(size: 10, letterSpacing: 0.5, color: MC.mute),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Scrollable item list
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 20),
              children: [
                ...sessions.map(_seanceRow),
                ...vetoInvites.map(_vetoRow),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Séance banner — highest priority, persistent until joined or séance ends ──
class _SeanceBanner extends StatelessWidget {
  final SeanceSession session;
  final VoidCallback onJoin;
  final VoidCallback onDismiss;

  const _SeanceBanner({
    required this.session,
    required this.onJoin,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1210),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFE8A13C).withOpacity(0.55),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.55),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                const Text('🕯️', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${session.hostName} has opened a séance',
                        style: const TextStyle(
                          color: MC.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        'The cult is gathering — join now',
                        style: MT.mono(size: 10, letterSpacing: 0.8, color: MC.mute),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onJoin,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: MC.accent1,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Join',
                      style: TextStyle(
                        color: MC.accentInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
      ),
    );
  }
}
