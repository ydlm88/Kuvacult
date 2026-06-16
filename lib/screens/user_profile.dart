import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../services/api_service.dart';

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String initialName;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.initialName = '',
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  List<Review> _reviews = [];
  bool _loading = true;
  late final TabController _tabCtrl;
  int _followerCount = 0;
  int _followingCount = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final requesterId = state.currentUser?.id;
    try {
      final results = await Future.wait([
        ApiService.fetchUser(widget.userId, requesterId: requesterId),
        state.loadUserReviews(widget.userId),
        ApiService.fetchUserSocialStats(widget.userId),
      ]);
      if (mounted) {
        final socialStats = results[2] as Map<String, dynamic>;
        setState(() {
          _profile = results[0] as Map<String, dynamic>;
          _reviews = results[1] as List<Review>;
          _followerCount =
              (socialStats['followerCount'] as num?)?.toInt() ?? 0;
          _followingCount =
              (socialStats['followingCount'] as num?)?.toInt() ?? 0;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _reviews = state.reviewsForUser(widget.userId);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final myId = state.currentUser?.id;
    final isMe = myId == widget.userId;

    final displayName = _profile?['displayName'] as String? ??
        (widget.initialName.isNotEmpty ? widget.initialName : widget.userId);
    final username = _profile?['username'] as String? ?? widget.userId;
    final friendCount = (_profile?['friendIds'] as List?)?.length ?? 0;
    final bio = _profile?['bio'] as String?;

    final colors = [
      const Color(0xFFF6C453), const Color(0xFF7AB9F2),
      const Color(0xFFE98AA8), const Color(0xFF85C9A8), const Color(0xFFB39DDB),
    ];
    final avatarColor = colors[widget.userId.hashCode.abs() % colors.length];
    final avatarUrl = _profile?['avatarUrl'] as String?;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: MC.bg0,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Back button + gradient header ──────────────────────────
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        avatarColor.withAlpha(40),
                        MC.bg0,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: MC.ink, size: 18),
                          ),
                          const SizedBox(height: 20),

                          // ── Avatar + name block ────────────────────────
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // Avatar
                              Container(
                                width: 72, height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: avatarColor,
                                  border: Border.all(color: MC.accent1, width: 2),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: avatarUrl != null
                                    ? Image.network(avatarUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: Text(initial,
                                              style: const TextStyle(
                                                  fontSize: 30,
                                                  fontWeight: FontWeight.w700,
                                                  color: MC.accentInk)),
                                        ))
                                    : Center(
                                        child: Text(initial,
                                            style: const TextStyle(
                                                fontSize: 30,
                                                fontWeight: FontWeight.w700,
                                                color: MC.accentInk)),
                                      ),
                              ),
                              const SizedBox(width: 16),
                              if (_loading)
                                const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      color: MC.accent1, strokeWidth: 2),
                                )
                              else
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(displayName, style: MT.display(size: 24)),
                                      Text('@$username',
                                          style: MT.mono(
                                              size: 11, letterSpacing: 1,
                                              color: MC.mute)),
                                      if (bio != null && bio.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(bio,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: MC.mute,
                                                height: 1.4),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // ── Stats row ──────────────────────────────────
                          Row(
                            children: [
                              _StatPill(
                                  label: 'Reviews',
                                  value: '${_reviews.length}',
                                  color: MC.marqueeScore),
                              const SizedBox(width: 8),
                              _StatPill(
                                  label: 'Followers',
                                  value: '$_followerCount',
                                  color: MC.ink),
                              const SizedBox(width: 8),
                              _StatPill(
                                  label: 'Following',
                                  value: '$_followingCount',
                                  color: MC.ink),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // ── Follow button (not self) ───────────────────
                          if (!isMe)
                            Builder(
                              builder: (ctx) {
                                final following =
                                    context.watch<AppState>().isFollowing(
                                        widget.userId);
                                return Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          if (following) {
                                            context
                                                .read<AppState>()
                                                .unfollowUser(widget.userId);
                                          } else {
                                            context
                                                .read<AppState>()
                                                .followUser(widget.userId);
                                          }
                                        },
                                        child: Container(
                                          height: 38,
                                          decoration: BoxDecoration(
                                            gradient: following
                                                ? null
                                                : const LinearGradient(
                                                    colors: [
                                                      MC.marqueeScore,
                                                      Color(0xFF3AB8BF)
                                                    ]),
                                            color: following
                                                ? MC.marqueeScore
                                                    .withAlpha(30)
                                                : null,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: following
                                                ? Border.all(
                                                    color: MC.marqueeScore,
                                                    width: 1)
                                                : null,
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            following ? 'Following' : 'Follow',
                                            style: TextStyle(
                                              color: following
                                                  ? MC.marqueeScore
                                                  : MC.marqueeScoreInk,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Tab bar ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: MC.bg1,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TabBar(
                      controller: _tabCtrl,
                      indicator: BoxDecoration(
                        color: MC.bg2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelStyle: MT.mono(
                          size: 10, letterSpacing: 1.5, color: MC.ink,
                          weight: FontWeight.w600),
                      unselectedLabelStyle: MT.mono(
                          size: 10, letterSpacing: 1.5, color: MC.dim),
                      tabs: const [
                        Tab(text: 'REVIEWS'),
                        Tab(text: 'ABOUT'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _ReviewsTab(reviews: _reviews, state: state),
            _AboutTab(profile: _profile, displayName: displayName,
                username: username, friendCount: friendCount),
          ],
        ),
      ),
    );
  }
}

// ─── Reviews tab ─────────────────────────────────────────────────────────────

class _ReviewsTab extends StatelessWidget {
  final List<Review> reviews;
  final AppState state;

  const _ReviewsTab({required this.reviews, required this.state});

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No public reviews yet.',
            style: TextStyle(color: MC.dim, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      itemCount: reviews.length,
      itemBuilder: (context, i) {
        final review = reviews[i];
        return _ProfileReviewCard(
          review: review,
          onLike: () => state.likeReview(review.id),
        );
      },
    );
  }
}

class _ProfileReviewCard extends StatelessWidget {
  final Review review;
  final VoidCallback onLike;

  const _ProfileReviewCard({required this.review, required this.onLike});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MC.bg1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MC.line, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: review.moviePosterUrl != null
                ? Image.network(review.moviePosterUrl!,
                    width: 40, height: 60, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder())
                : _placeholder(),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + year
                Text(review.movieTitle,
                    style: MT.display(size: 14, letterSpacing: -0.2),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${review.movieYear}',
                    style: MT.mono(size: 10, letterSpacing: 0, color: MC.dim)),
                const SizedBox(height: 6),

                // Stars
                _StarRow(stars: review.stars),
                const SizedBox(height: 6),

                // Text excerpt
                if (review.text.isNotEmpty)
                  Text(review.text,
                      style: const TextStyle(
                          fontSize: 13, color: MC.ink, height: 1.45),
                      maxLines: 3, overflow: TextOverflow.ellipsis),

                const SizedBox(height: 8),

                // Like + time
                Row(
                  children: [
                    GestureDetector(
                      onTap: onLike,
                      child: Row(children: [
                        Icon(
                          review.likedByMe
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 13,
                          color: review.likedByMe
                              ? const Color(0xFFE05A7A)
                              : MC.dim,
                        ),
                        const SizedBox(width: 3),
                        Text('${review.likes}',
                            style: MT.mono(
                                size: 9,
                                letterSpacing: 0,
                                color: review.likedByMe
                                    ? const Color(0xFFE05A7A)
                                    : MC.dim)),
                      ]),
                    ),
                    const Spacer(),
                    Text(_timeAgo(review.at),
                        style: MT.mono(size: 9, letterSpacing: 0, color: MC.dim)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 40, height: 60,
        decoration: BoxDecoration(
          color: MC.bg2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.movie_outlined, color: MC.dim, size: 16),
      );
}

// ─── About tab ────────────────────────────────────────────────────────────────

class _AboutTab extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final String displayName;
  final String username;
  final int friendCount;

  const _AboutTab({
    this.profile,
    required this.displayName,
    required this.username,
    required this.friendCount,
  });

  @override
  Widget build(BuildContext context) {
    final location = profile?['location'] as String?;
    final joined = profile?['createdAt'] as String?;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      children: [
        _InfoTile(icon: Icons.person_outline_rounded, label: 'Name', value: displayName),
        _InfoTile(icon: Icons.alternate_email_rounded, label: 'Username', value: '@$username'),
        if (location != null && location.isNotEmpty)
          _InfoTile(icon: Icons.location_on_outlined, label: 'Location', value: location),
        if (joined != null)
          _InfoTile(
            icon: Icons.calendar_today_outlined,
            label: 'Joined',
            value: _formatDate(joined),
          ),
        _InfoTile(
          icon: Icons.group_outlined,
          label: 'Friends',
          value: '$friendCount',
        ),
      ],
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, color: MC.dim, size: 18),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: MT.mono(size: 9, letterSpacing: 1.5)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14, color: MC.ink, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(50), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 6),
          Text(label, style: MT.mono(size: 10, letterSpacing: 0.5, color: MC.mute)),
        ],
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final double stars;
  const _StarRow({required this.stars});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = (i + 1) <= stars;
        final half = !filled && (i + 0.5) <= stars;
        return Padding(
          padding: const EdgeInsets.only(right: 1),
          child: Icon(
            half
                ? Icons.star_half_rounded
                : filled
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
            size: 13,
            color: MC.marqueeScore,
          ),
        );
      }),
    );
  }
}
