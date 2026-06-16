import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../mock_data.dart';
import '../models.dart';

class AvatarWidget extends StatelessWidget {
  final String memberId;
  final double size;
  final Color? ring;

  const AvatarWidget({
    super.key,
    required this.memberId,
    this.size = 24,
    this.ring,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final currentUser = state.currentUser;

    if (memberId == 'both') {
      return SizedBox(
        width: size * 1.5,
        height: size,
        child: Stack(
          children: [
            Positioned(left: 0, child: _circle(kMembers['mia']!, size * 0.75)),
            Positioned(
              right: 0, bottom: 0,
              child: _circle(kMembers['leo']!, size * 0.75),
            ),
          ],
        ),
      );
    }

    Member? member = kMembers[memberId];

    if (member == null && currentUser?.id == memberId) {
      member = Member(
        id: memberId,
        name: currentUser!.displayName,
        initial: currentUser.displayName.isNotEmpty
            ? currentUser.displayName[0].toUpperCase()
            : '?',
        avatarBg: currentUser.avatarBg,
      );
    }

    if (member == null) {
      // Check friends list, then watchlist member profiles
      UserAccount? profile;
      for (final friend in state.friends) {
        if (friend.id == memberId) { profile = friend; break; }
      }
      profile ??= state.memberProfiles[memberId];
      if (profile != null) {
        member = Member(
          id: memberId,
          name: profile.displayName,
          initial: profile.displayName.isNotEmpty
              ? profile.displayName[0].toUpperCase()
              : '?',
          avatarBg: profile.avatarBg,
        );
      }
    }

    member ??= Member(
      id: memberId,
      name: memberId,
      initial: '?',
      avatarBg: const Color(0xFF555555),
    );

    // Check if this user has a cloud avatar URL
    String? avatarUrl;
    if (currentUser?.id == memberId) {
      avatarUrl = currentUser?.avatarUrl;
    } else {
      for (final friend in state.friends) {
        if (friend.id == memberId) { avatarUrl = friend.avatarUrl; break; }
      }
      avatarUrl ??= state.memberProfiles[memberId]?.avatarUrl;
    }

    if (avatarUrl != null && avatarUrl.startsWith('http')) {
      return _networkCircle(avatarUrl, size);
    }
    return _circle(member, size);
  }

  Widget _networkCircle(String url, double s) {
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring != null ? Border.all(color: ring!, width: 1.5) : null,
      ),
      child: ClipOval(
        child: Image.network(
          url,
          width: s,
          height: s,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _circle(Member m, double s) {
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: m.avatarBg,
        border: ring != null
            ? Border.all(color: ring!, width: 1.5)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        m.initial,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: s * 0.42,
          color: Colors.black.withAlpha(180),
          height: 1,
        ),
      ),
    );
  }
}
