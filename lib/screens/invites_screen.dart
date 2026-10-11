// invites_screen.dart — Displays received and sent watchlist invites with accept/decline actions.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../services/api_service.dart';

class InvitesScreen extends StatefulWidget {
  const InvitesScreen({super.key});

  @override
  State<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends State<InvitesScreen> {
  List<Map<String, dynamic>> _sentInvites = [];
  bool _loadingSent = false;
  String? _sentError;

  @override
  void initState() {
    super.initState();
    _loadSent();
  }

  Future<void> _loadSent() async {
    final state = context.read<AppState>();
    final userId = state.currentUser?.id;
    if (userId == null) return;
    setState(() {
      _loadingSent = true;
      _sentError = null;
    });
    try {
      final results = await ApiService.fetchSentInvites(userId);
      if (!mounted) return;
      setState(() {
        _sentInvites = results;
        _loadingSent = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sentError = e.toString();
        _loadingSent = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final received = state.pendingInvites;

    return Scaffold(
      backgroundColor: MC.bg0,
      appBar: AppBar(
        backgroundColor: MC.bg0,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: MC.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Invites',
          style: MT.display(size: 17).copyWith(color: MC.ink),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                'RECEIVED',
                style: MT.mono(size: 10, letterSpacing: 2, color: MC.dim),
              ),
            ),
          ),
          if (received.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'No pending invites.',
                  style: MT.mono(size: 12, letterSpacing: 0, color: MC.dim),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final invite = received[index];
                  return _ReceivedInviteTile(
                    invite: invite,
                    onAccept: () async {
                      await state.acceptWatchlistInvite(
                        invite.watchlistId,
                        invite.id,
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
                    onDecline: () {
                      state.declineWatchlistInvite(
                        invite.watchlistId,
                        invite.id,
                      );
                    },
                  );
                },
                childCount: received.length,
              ),
            ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                'SENT',
                style: MT.mono(size: 10, letterSpacing: 2, color: MC.dim),
              ),
            ),
          ),
          if (_loadingSent)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_sentError != null || _sentInvites.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'No pending sent invites.',
                  style: MT.mono(size: 12, letterSpacing: 0, color: MC.dim),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final invite = _sentInvites[index];
                  return _SentInviteTile(invite: invite);
                },
                childCount: _sentInvites.length,
              ),
            ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 120),
          ),
        ],
      ),
    );
  }
}


class _ReceivedInviteTile extends StatelessWidget {
  const _ReceivedInviteTile({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  final WatchlistInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: MC.bg1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MC.line, width: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.remove_red_eye_outlined, color: MC.dim, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invite.watchlistName,
                    style: MT.mono(size: 13, letterSpacing: 0, color: MC.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${invite.inviterName}',
                    style: MT.mono(size: 12, letterSpacing: 0, color: MC.dim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAccept,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: MC.accent1,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Join',
                  style: MT.mono(size: 12, letterSpacing: 0, color: MC.accentInk),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDecline,
              child: Icon(Icons.close, color: MC.dim, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}


class _SentInviteTile extends StatelessWidget {
  const _SentInviteTile({required this.invite});

  final Map<String, dynamic> invite;

  @override
  Widget build(BuildContext context) {
    final watchlistName = invite['watchlistName'] as String? ?? '';
    final inviteeHandle = invite['inviteeHandle'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: MC.bg1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MC.line, width: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.send_outlined, color: MC.dim, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    watchlistName,
                    style: MT.mono(size: 13, letterSpacing: 0, color: MC.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '-> @$inviteeHandle',
                    style: MT.mono(size: 12, letterSpacing: 0, color: MC.dim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
