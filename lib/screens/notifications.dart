// notifications.dart — Unified notifications screen for friend requests, watchlist invites, veto invites, and activity.
import 'package:flutter/material.dart';
import '../widgets/app_image.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../theme.dart';
import 'user_profile.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final myId = state.currentUser?.id ?? '';

    final friendRequests = state.friendRequests
        .where((r) => r.toId == myId && !r.accepted)
        .toList();
    final wlInvites = state.pendingInvites;
    final vetoInvite = state.pendingVetoInvite;
    final rtNotifs = state.notifications;

    final hasRequests =
        friendRequests.isNotEmpty || wlInvites.isNotEmpty || vetoInvite != null;
    final hasActivity = rtNotifs.isNotEmpty;

    return Scaffold(
      backgroundColor: MC.bg0,
      appBar: AppBar(
        backgroundColor: MC.bg0,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: MC.ink, size: 18),
        ),
        title: Text('Notifications', style: MT.display(size: 20)),
        actions: [
          if (rtNotifs.any((n) => !n.read))
            GestureDetector(
              onTap: () => context.read<AppState>().markAllNotificationsRead(),
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('Mark all read',
                    style: MT.mono(size: 10, letterSpacing: 1, color: MC.accent1)),
              ),
            ),
        ],
      ),
      body: (hasRequests || hasActivity)
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                if (hasRequests) ...[
                  _sectionHeader('REQUESTS'),
                  if (vetoInvite != null)
                    _VetoTile(invite: vetoInvite),
                  ...wlInvites.map((inv) => _WatchlistInviteTile(invite: inv)),
                  ...friendRequests.map((req) => _FriendRequestTile(req: req)),
                  const SizedBox(height: 8),
                ],

                if (hasActivity) ...[
                  _sectionHeader('ACTIVITY'),
                  ...rtNotifs.map((n) => _ActivityTile(notif: n)),
                  const SizedBox(height: 8),
                ],
              ],
            )
          : _emptyState(),
    );
  }

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(label, style: MT.mono(size: 10, letterSpacing: 2, color: MC.dim)),
      );

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.notifications_none_rounded,
                  color: MC.dim, size: 48),
              const SizedBox(height: 16),
              Text('All caught up',
                  style: MT.display(size: 20, color: MC.ink)),
              const SizedBox(height: 8),
              const Text(
                'Friend requests, watchlist invites,\nlikes and follows will show up here.',
                style: TextStyle(color: MC.mute, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

class _VetoTile extends StatelessWidget {
  final VetoInvite invite;
  const _VetoTile({required this.invite});

  @override
  Widget build(BuildContext context) {
    return _NotifCard(
      icon: Icons.sports_esports_outlined,
      iconColor: MC.kuvacultScore,
      title: '${invite.fromName} invited you to Veto',
      subtitle: invite.watchlistName,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SmallButton(
            label: 'Dismiss',
            onTap: () => context.read<AppState>().dismissVetoInvite(),
          ),
          const SizedBox(width: 8),
          _SmallButton(
            label: 'Join',
            primary: true,
            onTap: () {
              context.read<AppState>().acceptVetoInvite();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class _WatchlistInviteTile extends StatefulWidget {
  final WatchlistInvite invite;
  const _WatchlistInviteTile({required this.invite});

  @override
  State<_WatchlistInviteTile> createState() => _WatchlistInviteTileState();
}

class _WatchlistInviteTileState extends State<_WatchlistInviteTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final inv = widget.invite;
    final rawUrl = inv.inviterAvatarUrl;
    final url = rawUrl != null && rawUrl.isNotEmpty
        ? (rawUrl.startsWith('/') ? '${Config.httpBase}$rawUrl' : rawUrl)
        : null;

    return _NotifCard(
      avatarUrl: url,
      avatarName: inv.inviterName,
      title: '${inv.inviterName} invited you to',
      subtitle: inv.watchlistName,
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: MC.accent1, strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SmallButton(
                  label: 'Decline',
                  onTap: () async {
                    setState(() => _busy = true);
                    await context
                        .read<AppState>()
                        .declineWatchlistInvite(inv.watchlistId, inv.id);
                  },
                ),
                const SizedBox(width: 8),
                _SmallButton(
                  label: 'Accept',
                  primary: true,
                  onTap: () async {
                    setState(() => _busy = true);
                    await context
                        .read<AppState>()
                        .acceptWatchlistInvite(inv.watchlistId, inv.id);
                  },
                ),
              ],
            ),
    );
  }
}

class _FriendRequestTile extends StatefulWidget {
  final FriendRequest req;
  const _FriendRequestTile({required this.req});

  @override
  State<_FriendRequestTile> createState() => _FriendRequestTileState();
}

class _FriendRequestTileState extends State<_FriendRequestTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final req = widget.req;
    final name = req.fromDisplayName?.isNotEmpty == true
        ? req.fromDisplayName!
        : (req.fromUsername ?? req.fromId);
    final rawUrl = req.fromAvatarUrl;
    final url = rawUrl != null && rawUrl.isNotEmpty
        ? (rawUrl.startsWith('/') ? '${Config.httpBase}$rawUrl' : rawUrl)
        : null;

    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => UserProfileScreen(userId: req.fromId))),
      child: _NotifCard(
        avatarUrl: url,
        avatarName: name,
        avatarId: req.fromId,
        title: name,
        subtitle: 'wants to be friends',
        trailing: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: MC.accent1, strokeWidth: 2))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SmallButton(
                    label: 'Decline',
                    onTap: () async {
                      setState(() => _busy = true);
                      await context
                          .read<AppState>()
                          .declineFriendRequest(req.id);
                    },
                  ),
                  const SizedBox(width: 8),
                  _SmallButton(
                    label: 'Accept',
                    primary: true,
                    onTap: () async {
                      setState(() => _busy = true);
                      await context
                          .read<AppState>()
                          .acceptFriendRequest(req.id);
                    },
                  ),
                ],
              ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final AppNotification notif;
  const _ActivityTile({required this.notif});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rawUrl = notif.fromAvatarUrl;
    final url = rawUrl != null && rawUrl.isNotEmpty
        ? (rawUrl.startsWith('/') ? '${Config.httpBase}$rawUrl' : rawUrl)
        : null;
    final handle =
        notif.fromHandle?.isNotEmpty == true ? '@${notif.fromHandle}' : null;

    String title;
    String subtitle;
    IconData? trailingIcon;
    Color? trailingColor;
    Widget? trailing;

    switch (notif.type) {
      case NotifType.likedReview:
        title = notif.fromName ?? 'Someone';
        subtitle = 'liked your review of ${notif.movieTitle ?? 'a movie'}';
        trailingIcon = Icons.favorite_rounded;
        trailingColor = const Color(0xFFE05A7A);
      case NotifType.likedWatchlist:
        title = notif.fromName ?? 'Someone';
        subtitle = 'liked your watchlist${notif.watchlistName != null ? ' "${notif.watchlistName}"' : ''}';
        trailingIcon = Icons.favorite_rounded;
        trailingColor = const Color(0xFFE05A7A);
      case NotifType.followed:
        title = notif.fromName ?? 'Someone';
        subtitle = handle != null ? '$handle followed you' : 'followed you';
        final alreadyFollowing = notif.fromId != null &&
            state.isFollowing(notif.fromId!);
        trailing = alreadyFollowing
            ? null
            : _SmallButton(
                label: 'Follow Back',
                primary: true,
                onTap: notif.fromId != null
                    ? () => context.read<AppState>().followUser(notif.fromId!)
                    : null,
              );
      default:
        title = 'Notification';
        subtitle = '';
    }

    if (trailing == null && trailingIcon != null) {
      trailing = Icon(trailingIcon, color: trailingColor, size: 18);
    }

    return GestureDetector(
      onTap: notif.fromId != null
          ? () {
              notif.read = true;
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          UserProfileScreen(userId: notif.fromId!)));
            }
          : null,
      child: _NotifCard(
        avatarUrl: url,
        avatarName: notif.fromName,
        avatarId: notif.fromId,
        title: title,
        subtitle: subtitle,
        timestamp: notif.at,
        unread: !notif.read,
        trailing: trailing,
      ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  final String? avatarUrl;
  final String? avatarName;
  final String? avatarId;
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final DateTime? timestamp;
  final bool unread;

  const _NotifCard({
    this.avatarUrl,
    this.avatarName,
    this.avatarId,
    this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.timestamp,
    this.unread = false,
  });

  @override
  Widget build(BuildContext context) {
    const double size = 40;
    final colors = [
      const Color(0xFFF6C453), const Color(0xFF7AB9F2),
      const Color(0xFFE98AA8), const Color(0xFF85C9A8), const Color(0xFFB39DDB),
    ];
    final avatarBg = avatarId != null
        ? colors[avatarId!.hashCode.abs() % colors.length]
        : colors[0];
    final initial = avatarName?.isNotEmpty == true
        ? avatarName![0].toUpperCase()
        : '?';

    Widget leftWidget;
    if (icon != null) {
      leftWidget = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: (iconColor ?? MC.accent1).withAlpha(25),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: iconColor ?? MC.accent1, size: 20),
      );
    } else if (avatarUrl != null) {
      leftWidget = ClipOval(
        child: AppImage(
          imageUrl: avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _initials(size, avatarBg, initial),
        ),
      );
    } else {
      leftWidget = _initials(size, avatarBg, initial);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: unread ? MC.accent1.withAlpha(12) : MC.bg1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unread ? MC.accent1.withAlpha(60) : MC.line,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          leftWidget,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 13, color: MC.ink, height: 1.35),
                    children: [
                      TextSpan(
                        text: title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: ' $subtitle'),
                    ],
                  ),
                ),
                if (timestamp != null) ...[
                  const SizedBox(height: 3),
                  Text(_timeAgo(timestamp!),
                      style: MT.mono(size: 9, letterSpacing: 0, color: MC.mute)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }

  Widget _initials(double size, Color bg, String initial) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
        alignment: Alignment.center,
        child: Text(initial,
            style: const TextStyle(
                color: MC.accentInk, fontWeight: FontWeight.w700, fontSize: 16)),
      );

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback? onTap;

  const _SmallButton({required this.label, this.primary = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: primary ? MC.accent1 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: primary ? MC.accent1 : MC.line,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primary ? MC.accentInk : MC.mute,
            fontSize: 12,
            fontWeight: primary ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
