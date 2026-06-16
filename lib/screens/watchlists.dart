import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models.dart';
import '../app_state.dart';
import '../widgets/avatar.dart';
import '../widgets/sign_in_sheet.dart';
import 'watchlist.dart';

class WatchlistsScreen extends StatefulWidget {
  const WatchlistsScreen({super.key});

  @override
  State<WatchlistsScreen> createState() => _WatchlistsScreenState();
}

class _WatchlistsScreenState extends State<WatchlistsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allLists = context.watch<AppState>().watchlists;
    final lists = _query.isEmpty
        ? allLists
        : allLists
            .where((wl) =>
                wl.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Scaffold(
      backgroundColor: MC.bg0,
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────────
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
                  _NewListButton(
                      onTap: () => _showCreateSheet(context)),
                ],
              ),
            ),
          ),

          // ── Search bar ───────────────────────────────────────────────────────
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
                          onChanged: (q) => setState(() => _query = q),
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
                            setState(() => _query = '');
                          },
                          child: const Icon(Icons.close_rounded,
                              color: MC.dim, size: 16),
                        ),
                    ],
                  ),
                ),
              ),
            ),

          // ── List or empty states ─────────────────────────────────────────────
          if (allLists.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyState(context))
          else if (lists.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text('No lists match "$_query"',
                    style: const TextStyle(color: MC.dim, fontSize: 13)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _WatchlistCard(
                    watchlist: lists[i],
                    onTap: () => _open(context, lists[i]),
                    onInvite: () => _showInviteSheet(context, lists[i]),
                    onRename: () => _showRenameSheet(context, lists[i]),
                    onDelete: () => _confirmDelete(context, lists[i]),
                  ),
                  childCount: lists.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────────────────
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

  // ── Navigation ────────────────────────────────────────────────────────────────
  void _open(BuildContext context, Watchlist wl) {
    context.read<AppState>().setActiveWatchlist(wl.id);
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const WatchlistScreen()));
  }

  // ── Create sheet ─────────────────────────────────────────────────────────────
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

  // ── Invite sheet ─────────────────────────────────────────────────────────────
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

  // ── Rename sheet ─────────────────────────────────────────────────────────────
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

  // ── Delete confirmation ───────────────────────────────────────────────────────
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
}

// ── New list button ───────────────────────────────────────────────────────────
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

// ── Watchlist card ────────────────────────────────────────────────────────────
class _WatchlistCard extends StatelessWidget {
  final Watchlist watchlist;
  final VoidCallback onTap;
  final VoidCallback onInvite;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _WatchlistCard({
    required this.watchlist,
    required this.onTap,
    required this.onInvite,
    required this.onRename,
    required this.onDelete,
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
            // Amber accent bar
            Container(
              width: 3,
              height: 52,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: MC.accent1,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Content
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
            // Overflow menu
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz,
                  color: MC.mute, size: 20),
              color: MC.bg2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (val) {
                switch (val) {
                  case 'invite':
                    onInvite();
                  case 'rename':
                    onRename();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'invite',
                  child: Row(children: const [
                    Icon(Icons.person_add_outlined,
                        color: MC.mute, size: 16),
                    SizedBox(width: 10),
                    Text('Invite',
                        style:
                            TextStyle(color: MC.ink, fontSize: 14)),
                  ]),
                ),
                PopupMenuItem(
                  value: 'rename',
                  child: Row(children: const [
                    Icon(Icons.edit_outlined,
                        color: MC.mute, size: 16),
                    SizedBox(width: 10),
                    Text('Rename',
                        style:
                            TextStyle(color: MC.ink, fontSize: 14)),
                  ]),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: const [
                    Icon(Icons.delete_outline_rounded,
                        color: Colors.redAccent, size: 16),
                    SizedBox(width: 10),
                    Text('Delete',
                        style: TextStyle(
                            color: Colors.redAccent, fontSize: 14)),
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

// ── Invite sheet ─────────────────────────────────────────────────────────────
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
        content: Text('${user.displayName} added to list',
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
          const Text('Share this code to invite collaborators',
              style: TextStyle(color: MC.mute, fontSize: 13)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: watchlist.listKey));
              ScaffoldMessenger.of(widget.parentContext).showSnackBar(
                SnackBar(
                  content: const Text('Code copied',
                      style: TextStyle(color: MC.ink, fontSize: 13)),
                  backgroundColor: MC.bg1,
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 104),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            child: Container(
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
                  const Icon(Icons.copy_rounded, color: MC.mute, size: 18),
                ],
              ),
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
                          child: const Text('Add',
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
