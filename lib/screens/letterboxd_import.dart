// letterboxd_import.dart — Import from Letterboxd page.
// Design reference: handoff dart/import_page.dart + reference/Import Page.dc.html
import 'dart:math' as math;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../services/api_service.dart';
import '../widgets/chalk_paint.dart';
import '../widgets/kuva_tokens.dart';

// Thin screen wrapper so profile.dart navigation needs no changes.
class LetterboxdImportScreen extends StatelessWidget {
  const LetterboxdImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LetterboxdImportPage(
      onBack: () => Navigator.pop(context),
      onImport: (path, onProgress) async {
        // Simulate incremental progress during the upload (single HTTP call,
        // no server-side streaming), then resolve to the real counts.
        var tick = 0;
        final ticker = Stream.periodic(const Duration(milliseconds: 180), (_) => tick++);
        final sub = ticker.listen((_) => onProgress(math.min(0.9, tick * 0.03)));
        try {
          final result = await ApiService.importLetterboxd(path);
          sub.cancel();
          onProgress(1.0);
          if (context.mounted) {
            final state = context.read<AppState>();
            state.refreshProfile().ignore();
            state.loadPublicReviews();
          }
          return ImportCounts(
            watched:    (result['watched']    as num?)?.toInt() ?? 0,
            watchlists: (result['watchlists'] as num?)?.toInt() ?? 0,
            ratings:    (result['ratings']    as num?)?.toInt() ?? 0,
          );
        } catch (_) {
          sub.cancel();
          rethrow;
        }
      },
    );
  }
}

// ─── Data ────────────────────────────────────────────────────────────────────

enum ImportPhase { idle, ready, importing, done }

class ImportCounts {
  const ImportCounts({this.watched = 0, this.watchlists = 0, this.ratings = 0});
  final int watched, watchlists, ratings;
}

typedef ImportRunner = Future<ImportCounts> Function(
    String path, void Function(double progress) onProgress);

// ─── Page ────────────────────────────────────────────────────────────────────

class LetterboxdImportPage extends StatefulWidget {
  const LetterboxdImportPage({super.key, required this.onImport, this.onBack});
  final ImportRunner onImport;
  final VoidCallback? onBack;

  @override
  State<LetterboxdImportPage> createState() => _LetterboxdImportPageState();
}

class _LetterboxdImportPageState extends State<LetterboxdImportPage> {
  ImportPhase _phase = ImportPhase.idle;
  bool _over = false;
  String? _path, _name;
  int _size = 0;
  double _p = 0;
  ImportCounts _result = const ImportCounts();
  String? _error;

  static const _steps = [
    'Open Letterboxd in your browser and sign in.',
    'Go to Settings → Data → Export your data.',
    'Download the ZIP file to your device.',
    'Choose the ZIP here, or drop it on the box.',
  ];

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['zip', 'csv']);
    final f = r?.files.single;
    if (f?.path != null) _setFile(f!.path!, f.name, f.size);
  }

  void _setFile(String path, String name, int size) => setState(() {
        _path = path; _name = name; _size = size;
        _p = 0; _phase = ImportPhase.ready; _over = false; _error = null;
      });

  Future<void> _start() async {
    setState(() { _phase = ImportPhase.importing; _error = null; });
    try {
      final counts = await widget.onImport(
          _path!, (p) { if (mounted) setState(() => _p = p.clamp(0, 1)); });
      if (!mounted) return;
      setState(() { _result = counts; _p = 1; _phase = ImportPhase.done; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _phase = ImportPhase.ready; _error = e.toString(); });
    }
  }

  void _reset() => setState(() {
        _phase = ImportPhase.idle; _path = _name = null; _p = 0; _error = null;
      });

  void _primary() {
    switch (_phase) {
      case ImportPhase.idle:     _pick();
      case ImportPhase.ready:    _start();
      case ImportPhase.importing: break;
      case ImportPhase.done:     _reset();
    }
  }

  String get _sizeLabel {
    final kb = _size / 1024;
    return kb > 1024
        ? '${(kb / 1024).toStringAsFixed(1)} MB'
        : '${math.max(1, kb.round())} KB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080707),
      body: Stack(children: [
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.5, -0.2),
                  radius: 0.9,
                  colors: [Color(0x14FFA647), Color(0x00000000)],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 26, 32, 60),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1116),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _topBar(),
                  const SizedBox(height: 44),
                  LayoutBuilder(builder: (_, c) {
                    final wide = c.maxWidth >= 860;
                    final left = _intro();
                    final right = _card();
                    return wide
                        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Padding(
                                padding: const EdgeInsets.only(top: 10), child: left)),
                            const SizedBox(width: 56),
                            Expanded(child: right),
                          ])
                        : Column(children: [left, const SizedBox(height: 40), right]);
                  }),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _topBar() => Row(children: [
        IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.chevron_left, color: Kuva.ink),
          style: IconButton.styleFrom(
              fixedSize: const Size(40, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
        const SizedBox(width: 18),
        Text('IMPORT FROM LETTERBOXD',
            style: Kuva.eyebrow.copyWith(fontSize: 11, color: Kuva.ink62)),
      ]);

  Widget _intro() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: "Don't start over.\n"),
            TextSpan(
                text: 'Bring your history.',
                style: TextStyle(fontStyle: FontStyle.italic, color: Kuva.flameFill)),
          ]),
          style: TextStyle(
              fontFamily: Kuva.panelTitle.fontFamily,
              fontSize: 60, height: 0.98, color: Kuva.inkBright),
        ),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            "Upload your Letterboxd export and we'll import your watched films and watchlist.",
            style: Kuva.subtitle.copyWith(
                fontSize: 14, height: 1.9, color: Kuva.ink.withValues(alpha: 0.76)),
          ),
        ),
        const SizedBox(height: 32),
        Text('HOW TO EXPORT', style: Kuva.eyebrow.copyWith(color: Kuva.amber)),
        const SizedBox(height: 14),
        for (var i = 0; i < _steps.length; i++) ...[
          _step(i),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Kuva.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x0FFFFFFF)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.info_outline, size: 14, color: Kuva.flameFill),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'A single '),
                  _code('watched.csv'),
                  const TextSpan(text: ', '),
                  _code('watchlist.csv'),
                  const TextSpan(text: ' or '),
                  _code('ratings.csv'),
                  const TextSpan(text: ' works too.'),
                ]),
                style: Kuva.subtitle.copyWith(
                    fontSize: 12, height: 1.7,
                    color: Kuva.ink.withValues(alpha: 0.66)),
              ),
            ),
          ]),
        ),
      ]);

  TextSpan _code(String t) =>
      TextSpan(text: t, style: const TextStyle(color: Color(0xFFF0D3A6)));

  Widget _step(int i) {
    final done = _phase == ImportPhase.done || (_phase != ImportPhase.idle && i < 3);
    return Row(children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 28, height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? const Color(0x24E8A13C) : Colors.transparent,
          border: Border.all(color: done ? Kuva.amber : const Color(0x66E8A13C)),
        ),
        child: Text(done ? '✓' : '${i + 1}',
            style: TextStyle(
                fontFamily: Kuva.hint.fontFamily,
                fontSize: 11,
                color: done ? Kuva.amber : Kuva.flameFill)),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Text(_steps[i],
            style: Kuva.subtitle.copyWith(
                fontSize: 13, height: 1.6,
                color: Kuva.ink.withValues(alpha: 0.84))),
      ),
    ]);
  }

  Widget _card() {
    final shown = _phase == ImportPhase.done
        ? 1.0
        : _phase == ImportPhase.importing
            ? Curves.easeOutCubic.transform(_p)
            : 0.0;
    final target = _phase == ImportPhase.done ? _result : null;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Kuva.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x47E8A13C)),
        boxShadow: const [
          BoxShadow(color: Color(0x99000000), blurRadius: 80, offset: Offset(0, 30))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _dropZone(),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_progLabel,
              style: Kuva.eyebrow.copyWith(fontSize: 10, letterSpacing: 1.8, color: Kuva.ink62)),
          Text('${(shown * 100).round()}%',
              style: Kuva.eyebrow.copyWith(fontSize: 10, letterSpacing: 1.8, color: Kuva.ink62)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            Container(height: 4, color: const Color(0x12FFFFFF)),
            FractionallySizedBox(
              widthFactor: shown,
              child: Container(
                height: 4,
                decoration: const BoxDecoration(
                  color: Kuva.amber,
                  boxShadow: [BoxShadow(color: Color(0x8CE8A13C), blurRadius: 12)],
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        Row(children: [
          _count('FILMS WATCHED', target?.watched, shown),
          const SizedBox(width: 10),
          _count('WATCHLISTS', target?.watchlists, shown),
          const SizedBox(width: 10),
          _count('RATINGS', target?.ratings, shown),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!,
              style: Kuva.subtitle.copyWith(fontSize: 11, color: Colors.redAccent)),
        ],
        const SizedBox(height: 18),
        _button(),
      ]),
    );
  }

  String get _progLabel => switch (_phase) {
        ImportPhase.idle      => 'WAITING FOR FILE',
        ImportPhase.ready     => 'READY',
        ImportPhase.importing => 'IMPORTING',
        ImportPhase.done      => 'IMPORT COMPLETE',
      };

  Widget _dropZone() {
    final marching = _over || _phase == ImportPhase.importing;
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (d) {
        final f = d.files.firstOrNull;
        if (f != null) f.length().then((len) => _setFile(f.path, f.name, len));
      },
      child: GestureDetector(
        onTap: (_phase == ImportPhase.idle || _phase == ImportPhase.done) ? _pick : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          constraints: const BoxConstraints(minHeight: 230),
          decoration: BoxDecoration(
            color: _over
                ? const Color(0x1AE8A13C)
                : _phase == ImportPhase.idle
                    ? const Color(0x04FFFFFF)
                    : const Color(0x0DE8A13C),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ChalkDashedBorder(
            marching: marching,
            opacity: marching ? 1 : 0.6,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _phase == ImportPhase.idle ? _idleContent() : _fileContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _idleContent() => Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.upload_file_outlined, size: 40, color: Kuva.flameFill),
        const SizedBox(height: 16),
        Text(_over ? 'Release to drop' : 'Drop your export here, or click to choose',
            textAlign: TextAlign.center,
            style: Kuva.subtitle.copyWith(fontSize: 13, color: Kuva.ink)),
        const SizedBox(height: 6),
        Text('ZIP or CSV from Letterboxd',
            style: Kuva.subtitle.copyWith(
                fontSize: 11, letterSpacing: 0.9,
                color: Kuva.ink.withValues(alpha: 0.6))),
      ]);

  Widget _fileContent() {
    final status = switch (_phase) {
      ImportPhase.ready     => 'READY TO IMPORT',
      ImportPhase.importing => 'SUMMONING YOUR FILMS…',
      ImportPhase.done      => 'WELCOME HOME.',
      _                     => '',
    };
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedRotation(
        turns: _phase == ImportPhase.ready ? -1 / 360 : 0,
        duration: const Duration(milliseconds: 600),
        curve: const Cubic(.2, .9, .3, 1.2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF161311),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x66E8A13C)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.description_outlined, size: 24, color: Kuva.flameFill),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(_name ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: Kuva.subtitle.copyWith(fontSize: 12, color: Kuva.ink)),
              ),
              const SizedBox(height: 3),
              Text(_sizeLabel,
                  style: Kuva.subtitle.copyWith(
                      fontSize: 10, letterSpacing: 0.8,
                      color: Kuva.ink.withValues(alpha: 0.6))),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Text(status,
          style: Kuva.eyebrow.copyWith(
              fontSize: 11,
              letterSpacing: 2.0,
              color: _phase == ImportPhase.done
                  ? Kuva.flameFill
                  : Kuva.ink.withValues(alpha: 0.66))),
    ]);
  }

  Widget _count(String label, int? target, double shown) {
    final v = target == null ? 0 : (target * shown).round();
    final color = _phase == ImportPhase.done
        ? Kuva.inkBright
        : shown > 0
            ? Kuva.ink
            : Kuva.ink.withValues(alpha: 0.35);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Kuva.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x0FFFFFFF)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$v',
              style: TextStyle(
                  fontFamily: Kuva.panelTitle.fontFamily,
                  fontSize: 32, height: 1, color: color)),
          const SizedBox(height: 5),
          Text(label, style: Kuva.liveLabel.copyWith(letterSpacing: 1.4, color: Kuva.ink62)),
        ]),
      ),
    );
  }

  Widget _button() {
    final done = _phase == ImportPhase.done;
    final label = switch (_phase) {
      ImportPhase.idle      => 'CHOOSE FILE',
      ImportPhase.ready     => 'BEGIN IMPORT',
      ImportPhase.importing => 'IMPORTING…',
      ImportPhase.done      => 'IMPORT ANOTHER',
    };
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _phase == ImportPhase.importing ? 0.6 : 1,
      child: GestureDetector(
        onTap: _primary,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? Colors.transparent : Kuva.amber,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: done ? const Color(0x80E8A13C) : Kuva.amber),
          ),
          child: Text(label,
              style: Kuva.eyebrow.copyWith(
                  fontSize: 12,
                  letterSpacing: 2.16,
                  color: done ? Kuva.ink : Kuva.onAmber)),
        ),
      ),
    );
  }
}

// ─── Chalk dashed border ─────────────────────────────────────────────────────

class ChalkDashedBorder extends StatefulWidget {
  const ChalkDashedBorder(
      {super.key, required this.child, this.marching = false, this.opacity = 0.6});
  final Widget child;
  final bool marching;
  final double opacity;

  @override
  State<ChalkDashedBorder> createState() => _ChalkDashedBorderState();
}

class _ChalkDashedBorderState extends State<ChalkDashedBorder>
    with TickerProviderStateMixin, ChalkBeat<ChalkDashedBorder> {
  late final AnimationController _march =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.marching) _march.repeat();
  }

  @override
  void didUpdateWidget(covariant ChalkDashedBorder old) {
    super.didUpdateWidget(old);
    if (widget.marching && !_march.isAnimating) _march.repeat();
    if (!widget.marching && _march.isAnimating) _march.stop();
  }

  @override
  void dispose() {
    _march.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedBuilder(
      animation: _march,
      builder: (_, child) => CustomPaint(
        foregroundPainter: _DashPainter(
          seed: reduce ? Chalk.seeds.first : chalkSeed,
          phase: reduce ? 0 : _march.value * 24,
          opacity: widget.opacity,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter({required this.seed, required this.phase, required this.opacity});
  final int seed;
  final double phase, opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outline = Chalk.roughen(
      Path()
        ..addRRect(RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(16))),
      seed,
      amplitude: 1.0,
      step: 4,
    );
    final paint = Chalk.stroke(Kuva.chalk.withValues(alpha: opacity), width: 1.6);
    const dash = 7.0, gap = 5.0;
    for (final m in outline.computeMetrics()) {
      double d = -phase % (dash + gap);
      while (d < m.length) {
        final a = math.max(0.0, d), b = math.min(m.length, d + dash);
        if (b > a) canvas.drawPath(m.extractPath(a, b), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter o) =>
      o.seed != seed || o.phase != phase || o.opacity != opacity;
}
