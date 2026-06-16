import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models.dart';
import '../mock_data.dart';
import '../app_state.dart';
import '../widgets/avatar.dart';
import '../widgets/poster.dart';
import '../widgets/chip_filter.dart';
import 'detail.dart';

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final allActivity = state.activity;
    final filtered = _filterActivity(allActivity);

    return Scaffold(
      backgroundColor: MC.bg0,
      body: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 62, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What you missed',
                      style: MT.mono(size: 10, letterSpacing: 2)),
                  const SizedBox(height: 4),
                  Text('Activity', style: MT.display(size: 34)),
                ],
              ),
            ),
          ),

          // ── Filter chips ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ChipFilter(
                items: const ['All', 'Notes', 'Reactions', 'Ratings', 'Moves'],
                active: _filter,
                onSelect: (s) => setState(() => _filter = s),
              ),
            ),
          ),

          // ── Activity list or empty state ───────────────────────────────────
          // TODO(backend): Paginate activity feed — GET /watchlists/:id/activity?page=N
          // Add pull-to-refresh to fetch latest events from the server.
          if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                child: Column(
                  children: [
                    const Icon(Icons.history_rounded,
                        color: MC.accent1, size: 36),
                    const SizedBox(height: 16),
                    Text('No activity yet', style: MT.display(size: 20)),
                    const SizedBox(height: 10),
                    const Text(
                      'Rate a movie, add a note, or react to something\nin your queue — it will show up here.',
                      style: TextStyle(
                          color: MC.mute, fontSize: 13, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => ActivityItem(
                    event: filtered[i],
                    isLast: i == filtered.length - 1,
                    onMovieTap: (movie) => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => DetailScreen(movie: movie)),
                    ),
                  ),
                  childCount: filtered.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  List<ActivityEvent> _filterActivity(List<ActivityEvent> all) {
    switch (_filter) {
      case 'Notes':
        return all.where((a) => a.kind == ActivityKind.note).toList();
      case 'Reactions':
        return all.where((a) => a.kind == ActivityKind.reacted).toList();
      case 'Ratings':
        return all.where((a) => a.kind == ActivityKind.rated).toList();
      case 'Moves':
        return all.where((a) => a.kind == ActivityKind.moved).toList();
      default:
        return all;
    }
  }
}

class ActivityItem extends StatelessWidget {
  final ActivityEvent event;
  final bool isLast;
  final ValueChanged<dynamic> onMovieTap;

  const ActivityItem({
    super.key,
    required this.event,
    required this.isLast,
    required this.onMovieTap,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final movie = event.movieId != null ? state.findMovie(event.movieId!) : null;
    final currentUser = state.currentUser;
    final profile = state.friends.cast<UserAccount?>()
        .firstWhere((f) => f?.id == event.who, orElse: () => null)
        ?? state.memberProfiles[event.who];
    final whoName = event.who == 'both'
        ? 'Everyone'
        : event.who == currentUser?.id
            ? currentUser!.displayName
            : (profile?.displayName ?? kMembers[event.who]?.name ?? '?');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: MC.line, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          AvatarWidget(memberId: event.who, size: 32),
          const SizedBox(width: 14),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Description text
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                        fontSize: 13, color: MC.mute, height: 1.4),
                    children: [
                      TextSpan(
                          text: whoName,
                          style: const TextStyle(
                              color: MC.ink, fontWeight: FontWeight.w600)),
                      const TextSpan(text: ' '),
                      ..._buildDescription(context, event, state),
                    ],
                  ),
                ),

                // Note quote
                if (event.kind == ActivityKind.note && event.text != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: MC.bg1,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: MC.line, width: 0.5),
                    ),
                    child: Text(
                      '"${event.text}"',
                      style: const TextStyle(
                          fontSize: 13, color: MC.ink, height: 1.45),
                    ),
                  ),
                ],

                // Veto pick posters
                if (event.kind == ActivityKind.vetoPick &&
                    event.picks != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: event.picks!.map((id) {
                      final m = state.findMovie(id);
                      if (m == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => onMovieTap(m),
                          child: PosterWidget(movie: m, width: 48, height: 72),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                // Timestamp
                const SizedBox(height: 6),
                Text(
                  _timeAgo(event.at),
                  style: MT.mono(size: 10, letterSpacing: 1),
                ),
              ],
            ),
          ),

          // Thumbnail (non-veto events with a movie)
          if (movie != null && event.kind != ActivityKind.vetoPick) ...[
            const SizedBox(width: 14),
            GestureDetector(
              onTap: () => onMovieTap(movie),
              child: PosterWidget(movie: movie, width: 36, height: 54),
            ),
          ],
        ],
      ),
    );
  }

  List<InlineSpan> _buildDescription(
      BuildContext context, ActivityEvent event, AppState state) {
    final movie = event.movieId != null ? state.findMovie(event.movieId!) : null;
    final titleSpan = movie != null
        ? TextSpan(
            text: movie.title,
            style: MT.display(
                size: 13, letterSpacing: 0, weight: FontWeight.w600))
        : null;

    switch (event.kind) {
      case ActivityKind.added:
        return [
          const TextSpan(text: 'added '),
          if (titleSpan != null) titleSpan,
          const TextSpan(text: ' to the queue'),
        ];
      case ActivityKind.reacted:
        return [
          const TextSpan(text: 'reacted '),
          TextSpan(
              text: event.reaction?.label ?? '',
              style: const TextStyle(color: MC.accent1)),
          const TextSpan(text: ' on '),
          if (titleSpan != null) titleSpan,
        ];
      case ActivityKind.note:
        return [
          const TextSpan(text: 'left a note on '),
          if (titleSpan != null) titleSpan,
        ];
      case ActivityKind.rated:
        return [
          const TextSpan(text: 'rated '),
          if (titleSpan != null) titleSpan,
          const TextSpan(text: ' '),
          TextSpan(
              text: '${event.stars != null ? (event.stars! % 1 == 0 ? event.stars!.toInt() : event.stars) : 0} stars',
              style: const TextStyle(color: MC.accent1)),
        ];
      case ActivityKind.moved:
        return [
          const TextSpan(text: 'moved '),
          if (titleSpan != null) titleSpan,
          const TextSpan(text: ' to '),
          TextSpan(
              text: event.to ?? '',
              style: const TextStyle(color: MC.accent1)),
        ];
      case ActivityKind.vetoPick:
        return [
          const TextSpan(text: 'started a Pick-3 Veto-2'),
        ];
      case ActivityKind.vetoed:
        return [
          const TextSpan(text: 'vetoed '),
          if (titleSpan != null) titleSpan,
        ];
      case ActivityKind.watched:
        return [
          const TextSpan(text: 'watched '),
          if (titleSpan != null) titleSpan,
          const TextSpan(text: ' together'),
        ];
    }
  }
}
