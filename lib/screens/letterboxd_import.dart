// letterboxd_import.dart — Screen for picking and uploading a Letterboxd ZIP/CSV export to migrate watched films and watchlists.
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme.dart';
import '../services/api_service.dart';

class LetterboxdImportScreen extends StatefulWidget {
  const LetterboxdImportScreen({super.key});

  @override
  State<LetterboxdImportScreen> createState() => _LetterboxdImportScreenState();
}

class _LetterboxdImportScreenState extends State<LetterboxdImportScreen> {
  _Phase _phase = _Phase.idle;
  String? _error;
  _ImportResult? _result;

  Future<void> _pickAndImport() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'csv'],
      withData: false,
      withReadStream: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null) return;

    setState(() { _phase = _Phase.loading; _error = null; });

    try {
      final result = await ApiService.importLetterboxd(path);
      if (mounted) {
        final state = context.read<AppState>();
        state.refreshProfile().ignore();
        state.loadPublicReviews();
        setState(() {
          _phase  = _Phase.done;
          _result = _ImportResult.fromJson(result);
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _phase = _Phase.idle; _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _phase = _Phase.idle; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.bg0,
      appBar: AppBar(
        backgroundColor: MC.bg0,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: MC.ink, size: 18),
        ),
        title: Text('Import from Letterboxd', style: MT.mono(size: 11, letterSpacing: 1.5)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.idle   => _buildIdle(),
          _Phase.loading => _buildLoading(),
          _Phase.done   => _buildDone(),
        },
      ),
    );
  }


  Widget _buildIdle() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: MC.bg1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MC.line, width: 0.5),
            ),
            child: Column(
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C030).withAlpha(20),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00C030).withAlpha(60)),
                  ),
                  child: const Icon(Icons.movie_filter_rounded,
                      color: Color(0xFF00C030), size: 26),
                ),
                const SizedBox(height: 14),
                Text('Migrate your list', style: MT.display(size: 20)),
                const SizedBox(height: 8),
                const Text(
                  'Upload your Letterboxd export and we\'ll import your watched films and watchlist',
                  style: TextStyle(color: MC.mute, fontSize: 13, height: 1.6),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
          Text('HOW TO EXPORT', style: MT.mono(size: 10, letterSpacing: 2)),
          const SizedBox(height: 14),

          _step('1', 'Open Letterboxd in your browser and sign in.'),
          _step('2', 'Go to Settings → Data → Export your data.'),
          _step('3', 'Download the ZIP file to your device.'),
          _step('4', 'Tap "Choose File" below and select the ZIP.'),

          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: MC.bg1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MC.line, width: 0.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: MC.mute, size: 16),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'You can also upload a single .csv file (watched.csv, watchlist.csv, or ratings.csv).',
                    style: TextStyle(color: MC.mute, fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12, height: 1.4)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),
          GestureDetector(
            onTap: _pickAndImport,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: MC.accent1,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.upload_file_rounded, color: MC.bg0, size: 18),
                  const SizedBox(width: 8),
                  Text('Choose File',
                      style: MT.mono(size: 12, letterSpacing: 1,
                          color: MC.bg0, weight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: MC.bg1,
              shape: BoxShape.circle,
              border: Border.all(color: MC.line, width: 0.5),
            ),
            alignment: Alignment.center,
            child: Text(num,
                style: MT.mono(size: 9, letterSpacing: 0, color: MC.mute)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: MC.ink, fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }


  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48, height: 48,
            child: CircularProgressIndicator(color: MC.accent1, strokeWidth: 2),
          ),
          const SizedBox(height: 24),
          Text('Looking up your movies…', style: MT.display(size: 18)),
          const SizedBox(height: 8),
          const Text('Checking IMDb, OMDB, and our catalog.',
              style: TextStyle(color: MC.mute, fontSize: 13)),
          const SizedBox(height: 4),
          const Text('This may take a minute.',
              style: TextStyle(color: MC.dim, fontSize: 12)),
        ],
      ),
    );
  }


  Widget _buildDone() {
    final r = _result!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: MC.bg1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MC.line, width: 0.5),
            ),
            child: Column(
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: MC.kuvacultScore.withAlpha(20),
                    shape: BoxShape.circle,
                    border: Border.all(color: MC.kuvacultScore.withAlpha(60)),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: MC.kuvacultScore, size: 30),
                ),
                const SizedBox(height: 14),
                Text('Import complete', style: MT.display(size: 22)),
                const SizedBox(height: 6),
                Text(
                  '${r.imported} of ${r.total} films added to your account',
                  style: const TextStyle(color: MC.mute, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Text('BREAKDOWN', style: MT.mono(size: 10, letterSpacing: 2)),
          const SizedBox(height: 12),

          if (r.watchedAdded > 0)
            _resultRow(
              icon: Icons.remove_red_eye_rounded,
              color: MC.accent1,
              label: 'Added to Watched',
              count: r.watchedAdded,
            ),
          if (r.watchlistsCreated > 0)
            _resultRow(
              icon: Icons.playlist_add_rounded,
              color: MC.kuvacultScore,
              label: 'Watchlists created',
              count: r.watchlistsCreated,
            ),
          if (r.reviewsImported > 0)
            _resultRow(
              icon: Icons.rate_review_rounded,
              color: MC.accent1,
              label: 'Reviews imported',
              count: r.reviewsImported,
            ),
          if (r.notFound > 0)
            _resultRow(
              icon: Icons.search_off_rounded,
              color: MC.mute,
              label: 'Not found (title unclear)',
              count: r.notFound,
            ),

          if (r.imported > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MC.bg1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MC.line, width: 0.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: MC.mute, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.watchlistsCreated > 0
                          ? 'Your Letterboxd watchlists are live in the Watchlists tab. Pull down to refresh if they don\'t appear yet. You can rename them or invite friends from there.'
                          : 'Your watched films have been added to your profile. Pull down on your profile to refresh if they don\'t appear yet.',
                      style: const TextStyle(color: MC.mute, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: MC.bg1,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MC.line, width: 0.5),
              ),
              alignment: Alignment.center,
              child: Text('Done', style: MT.mono(size: 12, letterSpacing: 1)),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() { _phase = _Phase.idle; _error = null; _result = null; }),
            child: Container(
              width: double.infinity,
              height: 44,
              alignment: Alignment.center,
              child: Text('Import another file',
                  style: MT.mono(size: 11, letterSpacing: 0.5, color: MC.mute)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultRow({
    required IconData icon,
    required Color color,
    required String label,
    required int count,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: MC.bg1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MC.line, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(color: MC.ink, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Text(
            '$count',
            style: MT.mono(size: 14, letterSpacing: 0, color: color, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}


enum _Phase { idle, loading, done }

class _ImportResult {
  final int imported;
  final int watchedAdded;
  final int watchlistsCreated;
  final int reviewsImported;
  final int notFound;
  final int total;

  const _ImportResult({
    required this.imported,
    required this.watchedAdded,
    required this.watchlistsCreated,
    required this.reviewsImported,
    required this.notFound,
    required this.total,
  });

  factory _ImportResult.fromJson(Map<String, dynamic> j) => _ImportResult(
    imported:          (j['imported']          as num? ?? 0).toInt(),
    watchedAdded:      (j['watchedAdded']      as num? ?? 0).toInt(),
    watchlistsCreated: (j['watchlistsCreated'] as num? ?? 0).toInt(),
    reviewsImported:   (j['reviewsImported']   as num? ?? 0).toInt(),
    notFound:          (j['notFound']          as num? ?? 0).toInt(),
    total:             (j['total']             as num? ?? 0).toInt(),
  );
}
