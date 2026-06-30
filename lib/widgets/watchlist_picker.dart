// watchlist_picker.dart — Bottom sheet and dialog for adding a movie to a watchlist, with smart single-list shortcut.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';

// Adds a movie to a watchlist. Behaviour depends on how many lists the user has
void showWatchlistPicker(BuildContext context, Movie movie) {
  final state = context.read<AppState>();
  final lists = state.watchlists;

  if (lists.isEmpty) {
    _promptCreateAndAdd(context, state, movie);
    return;
  }
  if (lists.length == 1) {
    final wl = lists.first;
    if (wl.movies.any((m) => m.id == movie.id)) {
      _showSnackBar(context, 'Already in ${wl.name}');
      return;
    }
    state.addMovieToWatchlist(movie, watchlistId: wl.id);
    _showSnackBar(context, 'Added to ${wl.name}');
    return;
  }
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: MC.bg1,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _PickerSheet(movie: movie),
  );
}

void _showSnackBar(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text, style: const TextStyle(color: MC.ink, fontSize: 13)),
    backgroundColor: MC.bg1,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

void _promptCreateAndAdd(BuildContext context, AppState state, Movie movie) {
  final ctrl = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: MC.bg1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Create a list first', style: TextStyle(color: MC.ink, fontSize: 18)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        style: const TextStyle(color: MC.ink),
        decoration: const InputDecoration(
          hintText: 'List name…',
          hintStyle: TextStyle(color: MC.dim),
          enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: MC.line)),
          focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: MC.accent1)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: MC.mute)),
        ),
        TextButton(
          onPressed: () async {
            final trimmed = ctrl.text.trim();
            if (trimmed.isNotEmpty) {
              final newWl = await state.createWatchlist(trimmed);
              if (!ctx.mounted) return;
              state.addMovieToWatchlist(movie, watchlistId: newWl.id);
              Navigator.pop(ctx);
              _showSnackBar(context, 'Added to ${newWl.name}');
            }
          },
          child: const Text('Create & Add',
              style: TextStyle(color: MC.accent1, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

class _PickerSheet extends StatefulWidget {
  final Movie movie;
  const _PickerSheet({required this.movie});

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final allLists = state.watchlists;
    final showSearch = allLists.length > 4;
    final lists = _search.isEmpty
        ? allLists
        : allLists
            .where((wl) =>
                wl.name.toLowerCase().contains(_search.toLowerCase()))
            .toList();
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: MC.dim, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Add to list', style: MT.display(size: 22)),
            ),
          ),
          if (showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(color: MC.ink, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search lists…',
                  hintStyle: const TextStyle(color: MC.dim, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: MC.dim, size: 16),
                  filled: true,
                  fillColor: MC.bg2,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
          Flexible(
            child: ListView.builder(
              itemCount: lists.length,
              itemBuilder: (ctx, i) {
                final wl = lists[i];
                final alreadyIn =
                    wl.movies.any((m) => m.id == widget.movie.id);
                return ListTile(
                  title: Text(wl.name,
                      style: const TextStyle(color: MC.ink, fontSize: 15)),
                  subtitle: Text(
                    '${wl.movies.length} ${wl.movies.length == 1 ? 'film' : 'films'}',
                    style: const TextStyle(color: MC.dim, fontSize: 12),
                  ),
                  trailing: alreadyIn
                      ? const Icon(Icons.check_rounded,
                          color: MC.accent1, size: 18)
                      : const Icon(Icons.add_rounded,
                          color: MC.mute, size: 18),
                  onTap: alreadyIn
                      ? null
                      : () {
                          state.addMovieToWatchlist(widget.movie,
                              watchlistId: wl.id);
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.pop(context);
                          messenger.showSnackBar(SnackBar(
                            content: Text('Added to ${wl.name}',
                                style: const TextStyle(
                                    color: MC.ink, fontSize: 13)),
                            backgroundColor: MC.bg1,
                            behavior: SnackBarBehavior.floating,
                            margin:
                                const EdgeInsets.fromLTRB(20, 0, 20, 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ));
                        },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
