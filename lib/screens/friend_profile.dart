// friend_profile.dart — Thin wrapper that resolves a friend by userId into the shared UserProfileScreen.
import 'package:flutter/material.dart';
import 'user_profile.dart';

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
