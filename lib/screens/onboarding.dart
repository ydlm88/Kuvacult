import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/poster.dart';
import 'auth.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.bg0,
      body: Stack(
        children: [
          // ── Angled poster collage — uses live trending movies from the API ────
          // Consumer rebuilds the collage whenever loadTrending() completes.
          // While the API call is in-flight the placeholders show gradient cards.
          Positioned(
            top: 60,
            left: -40,
            right: -40,
            height: 460,
            child: Transform.rotate(
              angle: -0.105, // ~-6 degrees
              child: Opacity(
                opacity: 0.85,
                child: Consumer<AppState>(
                  builder: (context, state, _) {
                    // Take up to 6 trending titles; fill remaining slots with placeholders
                    final movies = state.trendingMovies.take(6).toList();
                    final placeholderCount = 6 - movies.length;

                    return GridView.count(
                      crossAxisCount: 3,
                      padding: const EdgeInsets.all(20),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 110 / 165,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        // Real movie posters from the trending API response
                        ...movies.asMap().entries.map((e) =>
                          Transform.translate(
                            offset: Offset(0, (e.key % 2) * 30.0),
                            child: PosterWidget(
                                movie: e.value, width: 110, height: 165),
                          ),
                        ),
                        // Shimmer-like placeholder cards while the API loads
                        ...List.generate(placeholderCount, (i) =>
                          Transform.translate(
                            offset: Offset(0, ((movies.length + i) % 2) * 30.0),
                            child: _PlaceholderPoster(index: i),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),

          // ── Vignette gradient ──────────────────────────────────────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.30, 0.60, 0.85, 1.0],
                  colors: [
                    MC.bg0.withAlpha(0),
                    MC.bg0.withAlpha(238),
                    MC.bg0,
                    MC.bg0,
                  ],
                ),
              ),
            ),
          ),

          // ── Content ────────────────────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo row
                  Row(
                    children: [
                      _MarqueeLogo(),
                      const SizedBox(width: 8),
                      Text(
                        'MARQUEE',
                        style: MT.mono(size: 11, color: MC.mute, letterSpacing: 3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Headline
                  RichText(
                    text: TextSpan(
                      style: MT.display(size: 40, letterSpacing: -1.2),
                      children: [
                        const TextSpan(text: 'A watchlist\nfor '),
                        TextSpan(
                          text: 'two',
                          style: MT.display(
                            size: 40,
                            italic: true,
                            color: MC.accent1,
                            letterSpacing: -1.2,
                          ),
                        ),
                        const TextSpan(text: ',\nor a '),
                        TextSpan(
                          text: 'few',
                          style: MT.display(
                            size: 40,
                            italic: true,
                            letterSpacing: -1.2,
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Build a shared queue, pick what to watch tonight, and argue about it after.',
                    style: TextStyle(
                      fontSize: 14,
                      color: MC.mute,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Start room button
                  _PrimaryButton(
                    label: 'Start a new room',
                    onTap: () => _onStart(context),
                  ),
                  const SizedBox(height: 10),

                  // Join room button
                  _GhostButton(
                    label: 'Join with a code',
                    onTap: () => _onJoin(context),
                  ),
                  const SizedBox(height: 20),

                  Center(
                    child: Text(
                      'INVITE UP TO 6  ·  FREE FOREVER',
                      style: MT.mono(size: 10, letterSpacing: 2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onStart(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  void _onJoin(BuildContext context) {
    _showJoinDialog(context);
  }

  void _showJoinDialog(BuildContext context) {
    final controller = TextEditingController();
    bool joining = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: MC.bg1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Join a Watchlist', style: MT.display(size: 20)),
            content: TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: InputDecoration(
                hintText: 'Enter list key',
                hintStyle: const TextStyle(color: MC.dim),
                filled: true,
                fillColor: MC.bg2,
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: MC.ink, letterSpacing: 2),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: MC.mute)),
              ),
              TextButton(
                onPressed: joining ? null : () async {
                  setDialogState(() => joining = true);
                  try {
                    await context.read<AppState>().joinRoom(controller.text);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } finally {
                    if (ctx.mounted) setDialogState(() => joining = false);
                  }
                },
                child: joining
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(color: MC.accent1, strokeWidth: 2))
                    : const Text('Join', style: TextStyle(color: MC.accent1)),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Placeholder poster shown while trending API call is in-flight ─────────────
class _PlaceholderPoster extends StatelessWidget {
  final int index;
  const _PlaceholderPoster({required this.index});

  // Cycles through a few muted gradients so the placeholder collage looks intentional
  static const _gradients = [
    [Color(0xFF1A1A2E), Color(0xFF16213E)],
    [Color(0xFF0D1B2A), Color(0xFF1B2838)],
    [Color(0xFF1C1C1C), Color(0xFF2A2A2A)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[index % _gradients.length];
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
    );
  }
}

// ─── Marquee logo mark ─────────────────────────────────────────────────────────
class _MarqueeLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(24, 20),
      painter: _LogoPainter(),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MC.accent1
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.083, size.width * 0.417)
      ..lineTo(size.width * 0.5, size.width * 0.083)
      ..lineTo(size.width * 0.917, size.width * 0.417)
      ..lineTo(size.width * 0.917, size.height * 0.789)
      ..lineTo(size.width * 0.083, size.height * 0.789)
      ..close();
    canvas.drawPath(path, paint);

    final bulbPaint = Paint()
      ..color = MC.accent1
      ..style = PaintingStyle.fill;
    for (final x in [0.25, 0.417, 0.583, 0.75]) {
      canvas.drawCircle(Offset(size.width * x, size.height * 0.42), 0.9, bulbPaint);
    }

    canvas.drawLine(
      Offset(size.width * 0.208, size.height * 0.632),
      Offset(size.width * 0.792, size.height * 0.632),
      paint..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Button components ──────────────────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [MC.accent1, MC.accent2],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x44E8A93A),
              blurRadius: 20,
              offset: Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: MC.accentInk,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GhostButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MC.line, width: 0.5),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: MC.ink,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
