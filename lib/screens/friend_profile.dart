import 'package:flutter/material.dart';
import 'user_profile.dart';

// Thin alias so existing push calls in friends.dart / profile.dart need no changes.
class FriendProfileScreen extends StatelessWidget {
  final String userId;
  final String initialName;

  const FriendProfileScreen({
    super.key,
    required this.userId,
    this.initialName = '',
  });

  @override
  Widget build(BuildContext context) =>
      UserProfileScreen(userId: userId, initialName: initialName);
}
