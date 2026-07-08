// watchlists.dart — Lists all the user's watchlists with grid/list toggle, search, pagination, invite flow, and create/rename/delete/leave actions.

import 'package:flutter/material.dart';
import '../widgets/app_image.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models.dart';
import '../app_state.dart';
import '../widgets/avatar.dart';
import '../widgets/copy_button.dart';
import '../widgets/sign_in_sheet.dart';
import 'watchlist.dart';

class WatchlistsScreen extends StatefulWidget {
  const WatchlistsScreen({super.key});

  @override
  State<WatchlistsScreen> createState() => _WatchlistsScreenState();
}

class _WatchlistsScreenState extends State<WatchlistsScreen> {
  static const _kPageSize = 20;

  final _searchCtrl = TextEditingController();
  String _query    = '';
  bool _refreshing = false;
  bool _gridView   = false;
  int _page        = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh(AppState state) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await state.refreshProfile();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final allLists = state.watchlists;
    final currentUserId = state.currentUser?.id;
    final lists = _query.isEmpty
        ? allLists
        : allLists
            .where((wl) =>
                wl.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    final pageCount = lists.isEmpty ? 0 : (lists.length / _kPageSize).ceil();
    final page      = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final pageItems = lists.skip(page * _kPageSize).take(_kPageSize).toList();

    return Scaffold(
      backgroundColor: MC.bg0,
      body: RefreshIndicator(
        color: MC.accent1,
        backgroundColor: MC.bg1,
        onRefresh: () => _refresh(state),
        child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 62, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('YOUR COLLECTION',
                            style: MT.mono(size: 10, letterSpacing: 2)),
                        const SizedBox(height: 4),
                        Text('Watchlists', style: MT.display(size: 34)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _refresh(state),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: MC.line, width: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _refreshing
                          ? const SizedBox(
                              width: 15, height: 15,
                              child: CircularProgressIndicator(
                                  color: MC.mute, strokeWidth: 1.5))
                          : const Icon(Icons.refresh_rounded,
                              color: MC.mute, size: 15),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() { _gridView = !_gridView; _page = 0; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: MC.line, width: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _gridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                        color: MC.mute, size: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _NewListButton(
                      onTap: () => _showCreateSheet(context)),
                ],
              ),
            ),
          ),

          if (state.pendingInvites.isNotEmpty)
            SliverToBoxAdapter(
              child: _PendingInvitesSection(
                invites: state.pendingInvites,
                onAccept: (inv) => state.acceptWatchlistInvite(inv.watchlistId, inv.id),
                onDecline: (inv) => state.declineWatchlistInvite(inv.watchlistId, inv.id),
              ),
            ),

          if (allLists.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: MC.bg1,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MC.line, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: MC.mute, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (q) => setState(() { _query = q; _page = 0; }),
                          style: const TextStyle(
                              color: MC.ink, fontSize: 14, letterSpacing: -0.2),
                          decoration: const InputDecoration(
                            hintText: 'Search lists…',
                            hintStyle: TextStyle(color: MC.dim, fontSize: 14),
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                          ),
                          cursorColor: MC.accent1,
                        ),
                      ),
                      if (_query.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() { _query = ''; _page = 0; });
                          },
                          child: const Icon(Icons.close_rounded,
                              color: MC.dim, size: 16),
                        ),
                    ],
                  ),
                ),
              ),
            ),

          if (allLists.isEmpty && state.pendingInvites.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyState(context))
          else if (lists.isEmpty && _query.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text('No lists match "$_query"',
                    style: const TextStyle(color: MC.dim, fontSize: 13)),
              ),
            )
          else if (_gridView)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.68,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final wl = pageItems[i];
                    final isOwner = currentUserId != null &&
                        wl.memberIds.isNotEmpty &&
                        wl.memberIds[0] == currentUserId;
                    return _WatchlistGridCard(
                      key: ValueKey(wl.id),
                      watchlist: wl,
                      isOwner: isOwner,
                      onTap: () => _open(context, wl),
                      onInvite: () => _showInviteSheet(context, wl),
                      onRename: () => _showRenameSheet(context, wl),
                      onDelete: () => _confirmDelete(context, wl),
                      onLeave: () => _confirmLeave(context, wl),
                    );
                  },
                  findChildIndexCallback: (key) {
                    final id = (key as ValueKey<String>).value;
                    final idx = pageItems.indexWhere((wl) => wl.id == id);
                    return idx == -1 ? null : idx;
                  },
                  childCount: pageItems.length,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final wl = pageItems[i];
                    final isOwner = currentUserId != null &&
                        wl.memberIds.isNotEmpty &&
                        wl.memberIds[0] == currentUserId;
                    return _WatchlistCard(
                      key: ValueKey(wl.id),
                      watchlist: wl,
                      isOwner: isOwner,
                      onTap: () => _open(context, wl),
                      onInvite: () => _showInviteSheet(context, wl),
                      onRename: () => _showRenameSheet(context, wl),
                      onDelete: () => _confirmDelete(context, wl),
                      onLeave: () => _confirmLeave(context, wl),
                    );
                  },
                  findChildIndexCallback: (key) {
                    final id = (key as ValueKey<String>).value;
                    final idx = pageItems.indexWhere((wl) => wl.id == id);
                    return idx == -1 ? null : idx;
                  },
                  childCount: pageItems.length,
                ),
              ),
            ),

          if (pageCount > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: page > 0
                          ? () => setState(() => _page = page - 1)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: page > 0 ? MC.bg1 : MC.bg0,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: MC.line, width: 0.5),
                        ),
                        child: Text('← Prev',
                            style: TextStyle(
                                color: page > 0 ? MC.ink : MC.dim,
                                fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${page + 1} / $pageCount',
                      style: MT.mono(size: 11, letterSpacing: 0.5, color: MC.mute),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: page < pageCount - 1
                          ? () => setState(() => _page = page + 1)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: page < pageCount - 1 ? MC.bg1 : MC.bg0,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: MC.line, width: 0.5),
                        ),
                        child: Text('Next →',
                            style: TextStyle(
                                color: page < pageCount - 1 ? MC.ink : MC.dim,
                                fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
      child: Column(
        children: [
          Text('No lists yet.',
              style: MT.display(size: 26, italic: true, color: MC.mute)),
          const SizedBox(height: 10),
          const Text(
            'Create a list to start building your queue.',
            style: TextStyle(color: MC.dim, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => _showCreateSheet(context),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [MC.accent1, MC.accent2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Create your first list',
                style: TextStyle(
                    color: MC.accentInk,
                    fontWeight: FontWeight.w600,
                    fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Watchlist wl) {
    context.read<AppState>().setActiveWatchlist(wl.id);
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const WatchlistScreen()));
  }

  void _showCreateSheet(BuildContext context) {
    if (context.read<AppState>().isGuest) {
      showSignInSheet(context);
      return;
    }
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.bg1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: MC.dim, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text('New list', style: MT.display(size: 26)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: MC.ink, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'List name…',
                hintStyle: const TextStyle(color: MC.dim),
                filled: true,
                fillColor: MC.bg2,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: MC.accent1, width: 1)),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                if (ctrl.text.trim().isNotEmpty) {
                  context
                      .read<AppState>()
                      .createWatchlist(ctrl.text.trim());
                  Navigator.pop(ctx);
                }
              },
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [MC.accent1, MC.accent2]),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text('Create list',
                    style: TextStyle(
                        color: MC.accentInk,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInviteSheet(BuildContext context, Watchlist wl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.bg1,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _InviteSheet(watchlistId: wl.id, parentContext: context),
    );
  }

  void _showRenameSheet(BuildContext context, Watchlist wl) {
    if (context.read<AppState>().isGuest) {
      showSignInSheet(context);
      return;
    }
    final ctrl = TextEditingController(text: wl.name);
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.bg1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: MC.dim, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text('Rename', style: MT.display(size: 26)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: MC.ink, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'List name…',
                hintStyle: const TextStyle(color: MC.dim),
                filled: true,
                fillColor: MC.bg2,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: MC.accent1, width: 1)),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                if (ctrl.text.trim().isNotEmpty) {
                  context
                      .read<AppState>()
                      .renameWatchlist(wl.id, ctrl.text.trim());
                  Navigator.pop(ctx);
                }
              },
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [MC.accent1, MC.accent2]),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text('Save',
                    style: TextStyle(
                        color: MC.accentInk,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Watchlist wl) {
    if (context.read<AppState>().isGuest) {
      showSignInSheet(context);
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.bg1,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete "${wl.name}"?',
            style: const TextStyle(color: MC.ink)),
        content: Text(
          wl.movies.isEmpty
              ? 'This list will be permanently deleted.'
              : 'This will delete the list and all ${wl.movies.length} films in it.',
          style: const TextStyle(color: MC.mute, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: MC.mute)),
          ),
          TextButton(
            onPressed: () {
              context.read<AppState>().deleteWatchlist(wl.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmLeave(BuildContext context, Watchlist wl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.bg1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Leave "${wl.name}"?',
            style: const TextStyle(color: MC.ink)),
        content: const Text(
          'You will be removed from this list. The list stays for other members.',
          style: TextStyle(color: MC.mute, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: MC.mute)),
          ),
          TextButton(
            onPressed: () {
              context.read<AppState>().leaveWatchlist(wl.id);
              Navigator.pop(ctx);
            },
            child: const Text('Leave', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class _WatchlistGridCard extends StatelessWidget {
  final Watchlist watchlist;
  final bool isOwner;
  final VoidCallback onTap;
  final VoidCallback onInvite;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onLeave;

  const _WatchlistGridCard({
    super.key,
    required this.watchlist,
    required this.isOwner,
    required this.onTap,
    required this.onInvite,
    required this.onRename,
    required this.onDelete,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final count = watchlist.movies.length;
    final withPosters = watchlist.movies
        .where((m) => (m.poster.imageUrl ?? '').isNotEmpty)
        .take(4)
        .toList();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: MC.bg1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MC.line, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                child: _buildMosaic(withPosters),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(watchlist.name,
                            style: MT.display(size: 13, letterSpacing: -0.3),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('$count ${count == 1 ? 'film' : 'films'}',
                            style: MT.mono(size: 9, letterSpacing: 1, color: MC.mute)),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: MC.dim, size: 16),
                    color: MC.bg2,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    onSelected: (val) {
                      switch (val) {
                        case 'invite': onInvite();
                        case 'rename': onRename();
                        case 'delete': onDelete();
                        case 'leave':  onLeave();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'invite',
                        child: Row(children: const [
                          Icon(Icons.person_add_outlined, color: MC.mute, size: 16),
                          SizedBox(width: 10),
                          Text('Invite', style: TextStyle(color: MC.ink, fontSize: 14)),
                        ]),
                      ),
                      if (isOwner)
                        PopupMenuItem(
                          value: 'rename',
                          child: Row(children: const [
                            Icon(Icons.edit_outlined, color: MC.mute, size: 16),
                            SizedBox(width: 10),
                            Text('Rename', style: TextStyle(color: MC.ink, fontSize: 14)),
                          ]),
                        ),
                      if (isOwner)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: const [
                            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                            SizedBox(width: 10),
                            Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                          ]),
                        )
                      else
                        PopupMenuItem(
                          value: 'leave',
                          child: Row(children: const [
                            Icon(Icons.exit_to_app_rounded, color: Colors.redAccent, size: 16),
                            SizedBox(width: 10),
                            Text('Leave list', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                          ]),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMosaic(List<Movie> posters) {
    Widget img(Movie m) => SizedBox.expand(
      child: AppImage(
        imageUrl: m.poster.imageUrl!,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(color: MC.bg2),
      ),
    );

    if (posters.isEmpty) {
      return Container(
        color: MC.bg2,
        child: const Center(
          child: Icon(Icons.movie_outlined, color: MC.dim, size: 32),
        ),
      );
    }
    if (posters.length == 1) return img(posters[0]);
    if (posters.length < 4) {
      return Row(children: [
        Expanded(child: img(posters[0])),
        const SizedBox(width: 1),
        Expanded(child: img(posters[1])),
      ]);
    }
    return Column(children: [
      Expanded(child: Row(children: [
        Expanded(child: img(posters[0])),
        const SizedBox(width: 1),
        Expanded(child: img(posters[1])),
      ])),
      const SizedBox(height: 1),
      Expanded(child: Row(children: [
        Expanded(child: img(posters[2])),
        const SizedBox(width: 1),
        Expanded(child: img(posters[3])),
      ])),
    ]);
  }
}

class _NewListButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NewListButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: MC.accent1,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded,
                color: MC.accentInk, size: 16),
            const SizedBox(width: 4),
            const Text('New',
                style: TextStyle(
                    color: MC.accentInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _WatchlistCard extends StatelessWidget {
  final Watchlist watchlist;
  final bool isOwner;
  final VoidCallback onTap;
  final VoidCallback onInvite;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onLeave;

  const _WatchlistCard({
    super.key,
    required this.watchlist,
    required this.isOwner,
    required this.onTap,
    required this.onInvite,
    required this.onRename,
    required this.onDelete,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final count = watchlist.movies.length;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(0, 16, 8, 16),
        decoration: BoxDecoration(
          color: MC.bg1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MC.line, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 52,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: MC.accent1,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(watchlist.name,
                      style: MT.display(size: 18, letterSpacing: -0.5)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        '$count ${count == 1 ? 'film' : 'films'}',
                        style: MT.mono(
                            size: 10,
                            letterSpacing: 1,
                            color: MC.mute),
                      ),
                      if (watchlist.listKey.isNotEmpty) ...[
                        Text('  ·  ',
                            style: MT.mono(
                                size: 10, color: MC.dim)),
                        Text(watchlist.listKey,
                            style: MT.mono(
                                size: 10,
                                letterSpacing: 2,
                                color: MC.dim)),
                      ],
                    ],
                  ),
                  if (watchlist.memberIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: watchlist.memberIds
                          .take(5)
                          .toList()
                          .asMap()
                          .entries
                          .map((e) => Transform.translate(
                                offset: Offset(e.key * -6.0, 0),
                                child: AvatarWidget(
                                    memberId: e.value,
                                    size: 22,
                                    ring: MC.bg1),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz,
                  color: MC.mute, size: 20),
              color: MC.bg2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (val) {
                switch (val) {
                  case 'invite': onInvite();
                  case 'rename': onRename();
                  case 'delete': onDelete();
                  case 'leave':  onLeave();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'invite',
                  child: Row(children: const [
                    Icon(Icons.person_add_outlined, color: MC.mute, size: 16),
                    SizedBox(width: 10),
                    Text('Invite', style: TextStyle(color: MC.ink, fontSize: 14)),
                  ]),
                ),
                if (isOwner)
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(children: const [
                      Icon(Icons.edit_outlined, color: MC.mute, size: 16),
                      SizedBox(width: 10),
                      Text('Rename', style: TextStyle(color: MC.ink, fontSize: 14)),
                    ]),
                  ),
                if (isOwner)
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: const [
                      Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                      SizedBox(width: 10),
                      Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                    ]),
                  )
                else
                  PopupMenuItem(
                    value: 'leave',
                    child: Row(children: const [
                      Icon(Icons.exit_to_app_rounded, color: Colors.redAccent, size: 16),
                      SizedBox(width: 10),
                      Text('Leave list', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                    ]),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteSheet extends StatefulWidget {
  final String watchlistId;
  final BuildContext parentContext;

  const _InviteSheet(
      {required this.watchlistId, required this.parentContext});

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  bool _regenerating = false;
  final _searchCtrl = TextEditingController();
  List<UserAccount> _searchResults = [];
  bool _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _regenerate(AppState state) async {
    setState(() => _regenerating = true);
    try {
      await state.regenerateListKey(widget.watchlistId);
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _searchUsers(AppState state, String query) async {
    if (query.trim().isEmpty) {
      setState(() { _searchResults = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await state.searchUsers(query.trim());
      if (mounted) setState(() => _searchResults = results);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addMember(AppState state, UserAccount user) async {
    await state.addMemberToWatchlist(widget.watchlistId, user.id);
    if (!mounted) return;
    setState(() {
      _searchResults.removeWhere((u) => u.id == user.id);
      _searchCtrl.clear();
    });
    ScaffoldMessenger.of(widget.parentContext).showSnackBar(
      SnackBar(
        content: Text('Invite sent to ${user.displayName}',
            style: const TextStyle(color: MC.ink, fontSize: 13)),
        backgroundColor: MC.bg1,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 104),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final watchlist = state.watchlists.firstWhere(
      (w) => w.id == widget.watchlistId,
      orElse: () => state.watchlist,
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: MC.dim,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text('Invite to ${watchlist.name}',
              style: MT.display(size: 22)),
          const SizedBox(height: 4),
          const Text('They\'ll receive an invite to accept or decline',
              style: TextStyle(color: MC.mute, fontSize: 13)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: MC.bg2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MC.accent1.withAlpha(100), width: 0.5),
            ),
            child: Row(
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(watchlist.listKey,
                        style: MT.mono(size: 22, letterSpacing: 6, color: MC.accent1)),
                  ),
                ),
                const SizedBox(width: 12),
                CopyButton(text: watchlist.listKey, iconSize: 18, color: MC.mute),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _regenerating ? null : () => _regenerate(state),
            child: Row(
              children: [
                _regenerating
                    ? const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(color: MC.mute, strokeWidth: 1.5))
                    : const Icon(Icons.refresh_rounded, color: MC.mute, size: 14),
                const SizedBox(width: 6),
                Text('Regenerate code',
                    style: MT.mono(size: 10, color: MC.mute, letterSpacing: 1)),
              ],
            ),
          ),
          if (watchlist.memberIds.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('MEMBERS', style: MT.mono(size: 10, letterSpacing: 2)),
            const SizedBox(height: 10),
            Row(
              children: watchlist.memberIds
                  .map((id) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AvatarWidget(memberId: id, size: 32),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 20),
          Text('ADD BY USERNAME', style: MT.mono(size: 10, letterSpacing: 2)),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            onChanged: (q) => _searchUsers(state, q),
            style: const TextStyle(color: MC.ink, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Find by username',
              hintStyle: const TextStyle(color: MC.dim, fontSize: 14),
              prefixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: MC.mute, strokeWidth: 1.5)))
                  : const Icon(Icons.person_search_outlined, color: MC.mute, size: 18),
              filled: true,
              fillColor: MC.bg2,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._searchResults.map((user) {
              final alreadyMember = watchlist.memberIds.contains(user.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    AvatarWidget(memberId: user.id, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.displayName,
                              style: const TextStyle(color: MC.ink, fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                          Text('@${user.username}',
                              style: const TextStyle(color: MC.mute, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (alreadyMember)
                      Text('In list', style: MT.mono(size: 10, color: MC.mute, letterSpacing: 1))
                    else
                      GestureDetector(
                        onTap: () => _addMember(state, user),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: MC.accent1,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('Invite',
                              style: TextStyle(color: MC.accentInk, fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _PendingInvitesSection extends StatelessWidget {
  final List<WatchlistInvite> invites;
  final void Function(WatchlistInvite) onAccept;
  final void Function(WatchlistInvite) onDecline;

  const _PendingInvitesSection({
    required this.invites,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('INVITES', style: MT.mono(size: 10, letterSpacing: 2, color: MC.accent1)),
          const SizedBox(height: 8),
          ...invites.map((inv) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: MC.bg1,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MC.accent1.withAlpha(60), width: 0.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(inv.watchlistName,
                          style: const TextStyle(color: MC.ink, fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('from ${inv.inviterName}',
                          style: const TextStyle(color: MC.mute, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => onDecline(inv),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: MC.bg2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Decline', style: MT.mono(size: 10, color: MC.mute, letterSpacing: 1)),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => onAccept(inv),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: MC.accent1,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Accept', style: MT.mono(size: 10, color: MC.accentInk, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
