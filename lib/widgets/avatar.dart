// avatar.dart — Circular avatar that resolves a member ID to a network photo or an initialled colour circle.
import 'package:flutter/material.dart';
import 'app_image.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../kuva/kuva_avatar.dart';

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
    final state = context.watch<AppState>();
    final currentUser = state.currentUser;

    Member? member;

    if (currentUser?.id == memberId) {
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

    String? avatarUrl;
    AvatarBorder border = AvatarBorder.none;
    if (currentUser?.id == memberId) {
      avatarUrl = currentUser?.avatarUrl;
      border = currentUser?.avatarBorder ?? AvatarBorder.none;
    } else {
      UserAccount? profile;
      for (final friend in state.friends) {
        if (friend.id == memberId) { profile = friend; break; }
      }
      profile ??= state.memberProfiles[memberId];
      if (profile != null) {
        avatarUrl = profile.avatarUrl;
        border = profile.avatarBorder;
      }
    }

    if (border != AvatarBorder.none) {
      ImageProvider? image;
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        final url = avatarUrl.startsWith('http') ? avatarUrl : '${Config.httpBase}$avatarUrl';
        image = NetworkImage(url);
      }
      return KuvaAvatar(
        size: size,
        border: border,
        image: image,
        initial: member.initial,
        color: member.avatarBg,
        animate: false,
      );
    }

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      final resolvedUrl = avatarUrl.startsWith('http')
          ? avatarUrl
          : '${Config.httpBase}$avatarUrl';
      return _networkCircle(resolvedUrl, size);
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
        child: AppImage(
          imageUrl: url,
          width: s,
          height: s,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
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
