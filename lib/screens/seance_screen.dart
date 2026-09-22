// seance_screen.dart — Séance screen-share view.
// Layout: column [ header 64 | Expanded row( stage, 12 gap, member rail ) | controls ]
// Controls are always visible. Member rail collapses from 246 → 72px.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show DesktopCapturerSource, desktopCapturer, SourceType, ThumbnailSize;
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:livekit_client/livekit_client.dart';
import '../config.dart';
import '../services/seance_service.dart';
import '../widgets/candle_mark.dart';
import '../widgets/chalk_monitor.dart';

// ── Member model ─────────────────────────────────────────────────────────────

enum _SeanceRole { sharing, host, guest, away }

class _SeanceMember {
  const _SeanceMember({
    required this.name,
    required this.role,
    required this.tint,
    this.micOn = true,
    this.speaking = false,
    this.avatarUrl,
  });
  final String name;
  final _SeanceRole role;
  final Color tint;
  final bool micOn;
  final bool speaking;
  final String? avatarUrl;

  String get initials => name.length >= 2
      ? name.substring(0, 2).toUpperCase()
      : name.toUpperCase();

  String get roleLabel => switch (role) {
        _SeanceRole.sharing => 'SHARING',
        _SeanceRole.host => 'HOST',
        _SeanceRole.guest => 'GUEST',
        _SeanceRole.away => 'AWAY',
      };
}

Color _tintFor(String name) {
  const palette = [
    Color(0xFF4A3A2A), Color(0xFF2A3A4A), Color(0xFF3A2A4A),
    Color(0xFF2A4A3A), Color(0xFF4A2A3A), Color(0xFF3A4A2A),
  ];
  var h = 0;
  for (final c in name.codeUnits) h = (h * 31 + c) & 0xFFFFFFFF;
  return palette[h % palette.length];
}

// ── Screen ───────────────────────────────────────────────────────────────────

class SeanceScreen extends StatefulWidget {
  const SeanceScreen({
    super.key,
    required this.service,
    required this.isHost,
    required this.hostName,
    required this.hostId,
    this.hostAvatarUrl,
    this.currentUserId,
    this.currentUserName,
    this.currentUserAvatarUrl,
    required this.onEnded,
    this.onPopOut,
  });

  final SeanceService service;
  final bool isHost;
  final String hostName;
  final String hostId;
  final String? hostAvatarUrl;
  final String? currentUserId;
  final String? currentUserName;
  final String? currentUserAvatarUrl;
  final VoidCallback onEnded;
  final VoidCallback? onPopOut;

  @override
  State<SeanceScreen> createState() => _SeanceScreenState();
}

class _SeanceScreenState extends State<SeanceScreen> {
  bool _railOpen = true;
  bool _remoteEndHandled = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onServiceChange);
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceChange);
    super.dispose();
  }

  void _onServiceChange() {
    if (!mounted) return;
    if (widget.service.remoteEnded && !_remoteEndHandled) {
      _remoteEndHandled = true;
      if (widget.isHost) {
        widget.onEnded();
      } else {
        // Defer past the current build frame so showDialog has a clean navigator.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showEndedByHostDialog();
        });
      }
      return;
    }
    setState(() {});
  }

  Future<void> _showEndedByHostDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1612),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Séance Ended',
          style: GoogleFonts.newsreader(
              fontSize: 22, color: const Color(0xFFF4ECDE)),
        ),
        content: Text(
          '${widget.hostName} has ended the séance.',
          style: TextStyle(
            fontFamily: GoogleFonts.martianMono().fontFamily,
            fontSize: 12,
            color: const Color(0xBFF4ECDE),
            height: 1.6,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 12, 12),
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8A13C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'OK',
                  style: TextStyle(
                    fontFamily: GoogleFonts.martianMono().fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1B1210),
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (mounted) widget.onEnded();
  }

  List<_SeanceMember> _members() {
    // Derive host's mic state: local bool when hosting, remote track state when viewing.
    bool hostMicOn;
    if (widget.isHost) {
      hostMicOn = !widget.service.micMuted;
    } else {
      final hostParticipant = widget.service.viewers
          .where((v) => v.identity == widget.hostId)
          .firstOrNull;
      hostMicOn = hostParticipant != null ? !hostParticipant.isMuted : true;
    }

    final list = <_SeanceMember>[
      _SeanceMember(
        name: widget.hostName,
        role: _SeanceRole.sharing,
        tint: _tintFor(widget.hostName),
        micOn: hostMicOn,
        avatarUrl: widget.hostAvatarUrl,
      ),
    ];
    for (final v in widget.service.viewers) {
      if (v.identity == widget.hostId) continue;
      final n = v.name?.isNotEmpty == true ? v.name! : v.identity;
      list.add(_SeanceMember(
        name: n,
        role: _SeanceRole.guest,
        tint: _tintFor(n),
        micOn: !v.isMuted,
        avatarUrl: v.avatarUrl,
      ));
    }
    // Add the local user when they're a viewer (not in remoteParticipants)
    if (!widget.isHost && widget.currentUserName != null) {
      list.add(_SeanceMember(
        name: widget.currentUserName!,
        role: _SeanceRole.guest,
        tint: _tintFor(widget.currentUserName!),
        micOn: !widget.service.micMuted,
        avatarUrl: widget.currentUserAvatarUrl,
      ));
    }
    return list;
  }

  Future<void> _showMicPicker() async {
    final devices = await widget.service.availableMics();
    if (!mounted || devices.isEmpty) return;
    final currentId = widget.service.currentMicId;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1612),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x1FF4ECDE)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text('Select Microphone',
                  style: GoogleFonts.newsreader(
                      fontSize: 20, color: const Color(0xFFF4ECDE))),
            ),
            const Divider(height: 1, color: Color(0x14F4ECDE)),
            ...devices.map((d) {
              final isSelected = d.deviceId == currentId ||
                  (currentId == null && d == devices.first);
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  widget.service.switchMic(d.deviceId);
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0x0FF4ECDE)))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(d.label.isNotEmpty ? d.label : d.deviceId,
                            style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFFE8A13C)
                                    : const Color(0xFFF4ECDE),
                                fontSize: 14)),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_rounded,
                            size: 16, color: Color(0xFFE8A13C)),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showOutputPicker() async {
    final devices = await widget.service.availableOutputs();
    if (!mounted) return;
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No output devices found')),
      );
      return;
    }
    final currentDevice = widget.service.currentOutputDevice;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1612),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x1FF4ECDE)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text('Select Speaker',
                  style: GoogleFonts.newsreader(
                      fontSize: 20, color: const Color(0xFFF4ECDE))),
            ),
            const Divider(height: 1, color: Color(0x14F4ECDE)),
            ...devices.map((d) {
              final isSelected = d.deviceId == currentDevice?.deviceId ||
                  (currentDevice == null && d == devices.first);
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  widget.service.switchOutput(d);
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0x0FF4ECDE)))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(d.label.isNotEmpty ? d.label : d.deviceId,
                            style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFFE8A13C)
                                    : const Color(0xFFF4ECDE),
                                fontSize: 14)),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_rounded,
                            size: 16, color: Color(0xFFE8A13C)),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showScreenPicker() async {
    final sources = await widget.service.getDesktopSources();
    if (sources == null) {
      // Mobile/web: use default screen share
      try {
        await widget.service.toggleScreenShare();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Screen share failed: $e')),
          );
        }
      }
      return;
    }
    if (!mounted) return;
    final picked = await showDialog<DesktopCapturerSource>(
      context: context,
      builder: (_) => _ScreenPickerDialog(sources: sources),
    );
    if (picked == null || !mounted) return;
    try {
      await widget.service.toggleScreenShare(sourceId: picked.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Screen share failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Column(
        children: [
          SafeArea(bottom: false, child: _header()),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _stage()),
                  const SizedBox(width: 12),
                  _MemberRail(
                    members: _members(),
                    open: _railOpen,
                    onToggle: () => setState(() => _railOpen = !_railOpen),
                  ),
                ],
              ),
            ),
          ),
          _controls(context),
        ],
      ),
    );
  }

  Widget _header() => Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: const BoxDecoration(
          color: Color(0xFF0D0C0B),
          border: Border(bottom: BorderSide(color: Color(0x0FFFFFFF))),
        ),
        child: Row(children: [
          const CandleMark(size: 44),
          const SizedBox(width: 14),
          Text('Séance',
              style: GoogleFonts.newsreader(
                  fontSize: 21, color: const Color(0xFFF3E4CF))),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${widget.hostName} is sharing their screen',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: GoogleFonts.martianMono().fontFamily,
                fontSize: 10,
                color: const Color(0x9EF3E4CF),
                letterSpacing: 1.6,
              ),
            ),
          ),
          const _LiveChip(),
          const SizedBox(width: 14),
          const _ElapsedTimer(),
        ]),
      );

  Widget _stage() {
    final svc = widget.service;
    final remoteVideo = svc.remoteVideoTrack;
    final localVideo = svc.localScreenTrack;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF121010),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x28E8A13C)),
        boxShadow: const [
          BoxShadow(color: Color(0x8C000000), blurRadius: 50, offset: Offset(0, 20)),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.isHost && localVideo != null)
            VideoTrackRenderer(localVideo, fit: VideoViewFit.contain,
                key: ObjectKey(localVideo))
          else if (!widget.isHost && remoteVideo != null)
            VideoTrackRenderer(remoteVideo, fit: VideoViewFit.contain,
                key: ObjectKey(remoteVideo))
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ChalkMonitor(width: 100),
                  const SizedBox(height: 12),
                  Text(
                    widget.isHost
                        ? 'Your screen'
                        : "${widget.hostName}'s screen",
                    style: GoogleFonts.newsreader(
                        fontSize: 26, color: const Color(0xFFF3E4CF)),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 320,
                    child: Text(
                      widget.isHost
                          ? 'Press SHARE below to start sharing your screen.'
                          : 'Everyone in the séance sees this. Their view follows whatever is on the shared screen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: GoogleFonts.martianMono().fontFamily,
                        fontSize: 11,
                        color: const Color(0x8CF3E4CF),
                        height: 1.7,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Positioned(left: 14, top: 14, child: _sharingChip()),
        ],
      ),
    );
  }

  Widget _sharingChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xC70A0A0A),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x59E8A13C)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Color(0xFFE8A13C)),
          ),
          const SizedBox(width: 8),
          Text(
            '${widget.hostName.toUpperCase()} IS SHARING',
            style: TextStyle(
              fontFamily: GoogleFonts.martianMono().fontFamily,
              fontSize: 9,
              color: const Color(0xFFF3E4CF),
              letterSpacing: 1.6,
            ),
          ),
        ]),
      );

  Widget _controls(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    return AnimatedBuilder(
      animation: widget.service,
      builder: (_, __) {
        final svc = widget.service;
        final muted = svc.micMuted;
        final sharing = svc.isSharing;
        return Container(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomPad),
          decoration: const BoxDecoration(
            color: Color(0xFF0D0C0B),
            border: Border(top: BorderSide(color: Color(0x0FFFFFFF))),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _MicButtonGroup(
                muted: muted,
                onToggle: () => svc.toggleMic(),
                onPickMic: _showMicPicker,
              ),
              _ControlButton(
                icon: Icons.volume_up_outlined,
                label: 'SPEAKER',
                active: false,
                onTap: _showOutputPicker,
              ),
              if (widget.isHost)
                _ControlButton(
                  icon: sharing
                      ? Icons.stop_screen_share_outlined
                      : Icons.screen_share_outlined,
                  label: sharing ? 'STOP' : 'SHARE',
                  active: sharing,
                  onTap: sharing
                      ? () async {
                          try {
                            await svc.toggleScreenShare();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                          }
                        }
                      : _showScreenPicker,
                ),
              if (widget.isHost && sharing)
                _ControlButton(
                  icon: svc.screenAudioMuted
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                  label: svc.screenAudioMuted ? 'SYS MUTED' : 'SYS AUDIO',
                  active: svc.screenAudioMuted,
                  onTap: () => svc.toggleScreenAudio(),
                ),
              if (!widget.isHost)
                _ControlButton(
                  icon: svc.localScreenAudioMuted
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                  label: svc.localScreenAudioMuted ? 'SYS MUTED' : 'SYS AUDIO',
                  active: svc.localScreenAudioMuted,
                  onTap: () => svc.toggleLocalScreenAudio(),
                ),
              if (widget.onPopOut != null)
                _ControlButton(
                  icon: Icons.picture_in_picture_alt_outlined,
                  label: 'POP OUT',
                  active: false,
                  onTap: widget.onPopOut!,
                ),
              Container(
                width: 1,
                height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: const Color(0x14FFFFFF),
              ),
              GestureDetector(
                onTap: widget.onEnded,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0x29D34B3B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x8CD34B3B)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.close, size: 15, color: Color(0xFFF0B6AC)),
                    const SizedBox(width: 9),
                    Text(
                      widget.isHost ? 'END SÉANCE' : 'LEAVE SÉANCE',
                      style: TextStyle(
                        fontFamily: GoogleFonts.martianMono().fontFamily,
                        fontSize: 10,
                        color: const Color(0xFFF0B6AC),
                        letterSpacing: 1.8,
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Elapsed timer (own widget so it doesn't force full rebuilds) ─────────────

class _ElapsedTimer extends StatefulWidget {
  const _ElapsedTimer();
  @override
  State<_ElapsedTimer> createState() => _ElapsedTimerState();
}

class _ElapsedTimerState extends State<_ElapsedTimer> {
  late final Stopwatch _sw = Stopwatch()..start();
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String get _label {
    final e = _sw.elapsed;
    final m = e.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = e.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) => Text(
        _label,
        style: TextStyle(
          fontFamily: GoogleFonts.martianMono().fontFamily,
          fontSize: 10,
          color: const Color(0x9EF3E4CF),
          letterSpacing: 1.2,
        ),
      );
}

// ── Chalk monitor (animated) ─────────────────────────────────────────────────

// ── Screen source picker dialog (desktop only) ───────────────────────────────

class _ScreenPickerDialog extends StatefulWidget {
  const _ScreenPickerDialog({required this.sources});
  final List<DesktopCapturerSource> sources;

  @override
  State<_ScreenPickerDialog> createState() => _ScreenPickerDialogState();
}

class _ScreenPickerDialogState extends State<_ScreenPickerDialog> {
  DesktopCapturerSource? _selected;
  bool _showWindows = false;
  bool _refreshing = false;
  late List<DesktopCapturerSource> _sources = List.of(widget.sources);

  List<DesktopCapturerSource> get _filtered => _sources
      .where((s) => _showWindows
          ? s.type.name == 'Window'
          : s.type.name == 'Screen')
      .toList();

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final fresh = await desktopCapturer.getSources(
        types: [SourceType.Screen, SourceType.Window],
        thumbnailSize: ThumbnailSize(150, 150),
      );
      if (mounted) {
        setState(() {
          _sources = fresh;
          _refreshing = false;
          // Clear selection if the selected source is no longer in the list.
          if (_selected != null && !_sources.any((s) => s.id == _selected!.id)) {
            _selected = null;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1612),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  Text('Choose what to share',
                      style: GoogleFonts.newsreader(
                          fontSize: 20, color: const Color(0xFFF4ECDE))),
                  const Spacer(),
                  GestureDetector(
                    onTap: _refreshing ? null : _refresh,
                    child: _refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0x66F4ECDE),
                            ),
                          )
                        : const Icon(Icons.refresh, color: Color(0x66F4ECDE), size: 18),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Color(0x66F4ECDE), size: 18),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                _TabBtn(label: 'Screens', selected: !_showWindows,
                    onTap: () => setState(() => _showWindows = false)),
                _TabBtn(label: 'Windows', selected: _showWindows,
                    onTap: () => setState(() => _showWindows = true)),
                if (_showWindows)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        'Window must be visible to capture',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontFamily: GoogleFonts.martianMono().fontFamily,
                          fontSize: 9,
                          color: const Color(0x66F4ECDE),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 1, color: Color(0x14F4ECDE)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: _filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No sources found',
                          style: TextStyle(color: Color(0x66F4ECDE))),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      shrinkWrap: true,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 1.4),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final src = _filtered[i];
                        final sel = _selected?.id == src.id;
                        return GestureDetector(
                          onTap: () => setState(() => _selected = src),
                          child: Container(
                            decoration: BoxDecoration(
                              color: sel
                                  ? const Color(0x33E8A13C)
                                  : const Color(0x0FFFFFFF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: sel
                                    ? const Color(0xFFE8A13C)
                                    : const Color(0x14FFFFFF),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (src.thumbnail != null)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Image.memory(
                                        src.thumbnail!,
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
                                      ),
                                    ),
                                  )
                                else
                                  const Icon(Icons.desktop_windows_outlined,
                                      size: 32, color: Color(0x66F4ECDE)),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                                  child: Text(
                                    src.name,
                                    style: TextStyle(
                                      fontFamily: GoogleFonts.martianMono().fontFamily,
                                      fontSize: 9,
                                      color: const Color(0xCCF4ECDE),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0x33F4ECDE)),
                      ),
                      child: Text('Cancel',
                          style: TextStyle(
                              fontFamily: GoogleFonts.martianMono().fontFamily,
                              fontSize: 11,
                              color: const Color(0x99F4ECDE))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _selected == null
                        ? null
                        : () => Navigator.pop<DesktopCapturerSource>(
                            context, _selected),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: _selected != null
                            ? const Color(0xFFE8A13C)
                            : const Color(0x22E8A13C),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text('Share',
                          style: TextStyle(
                              fontFamily: GoogleFonts.martianMono().fontFamily,
                              fontSize: 11,
                              color: _selected != null
                                  ? const Color(0xFF1B1210)
                                  : const Color(0x66E8A13C))),
                    ),
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

class _TabBtn extends StatelessWidget {
  const _TabBtn(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: selected
                      ? const Color(0xFFE8A13C)
                      : Colors.transparent,
                  width: 2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: GoogleFonts.martianMono().fontFamily,
            fontSize: 10,
            letterSpacing: 1.2,
            color: selected
                ? const Color(0xFFE8A13C)
                : const Color(0x66F4ECDE),
          ),
        ),
      ),
    );
  }
}

// ── Member rail ───────────────────────────────────────────────────────────────

class _MemberRail extends StatelessWidget {
  const _MemberRail({
    required this.members,
    required this.open,
    required this.onToggle,
  });
  final List<_SeanceMember> members;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: const Cubic(.3, .9, .3, 1),
      width: open ? 246 : 72,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0C0B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x0FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              color: Colors.transparent,
              child: Row(children: [
                AnimatedRotation(
                  duration: const Duration(milliseconds: 260),
                  turns: open ? 0 : 0.5,
                  child: const Icon(Icons.chevron_left,
                      size: 18, color: Color(0xFFE8A13C)),
                ),
                if (open) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('CULT',
                        style: TextStyle(
                          fontFamily: GoogleFonts.martianMono().fontFamily,
                          fontSize: 9,
                          color: const Color(0x66F3E4CF),
                          letterSpacing: 2.0,
                        )),
                  ),
                ],
                if (open)
                  Text('${members.length}',
                      style: TextStyle(
                        fontFamily: GoogleFonts.martianMono().fontFamily,
                        fontSize: 10,
                        color: const Color(0x9EF3E4CF),
                        letterSpacing: 1.2,
                      )),
              ]),
            ),
          ),
          Container(height: 1, color: const Color(0x0FFFFFFF)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: members.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _MemberTile(m: members[i], open: open),
            ),
          ),
          if (open) ...[
            Container(height: 1, color: const Color(0x0FFFFFFF)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Text('Invite the cult',
                  style: TextStyle(
                    fontFamily: GoogleFonts.martianMono().fontFamily,
                    fontSize: 10,
                    color: const Color(0x66F3E4CF),
                    letterSpacing: 1.4,
                  )),
            ),
          ],
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.m, required this.open});
  final _SeanceMember m;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final away = m.role == _SeanceRole.away;
    final tile = Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: m.speaking
            ? const Color(0x14E8A13C)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        _MemberAvatar(m: m),
        if (open) ...[
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        color: away
                            ? const Color(0x8CF3E4CF)
                            : const Color(0xFFF3E4CF))),
                const SizedBox(height: 2),
                Text(m.roleLabel,
                    style: TextStyle(
                      fontFamily: GoogleFonts.martianMono().fontFamily,
                      fontSize: 9,
                      letterSpacing: 1.26,
                      color: m.role == _SeanceRole.sharing
                          ? const Color(0xFFE8A13C)
                          : const Color(0x66F3E4CF),
                    )),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(m.micOn ? Icons.mic_none : Icons.mic_off,
              size: 14,
              color: m.micOn
                  ? const Color(0x66F3E4CF)
                  : const Color(0xCCF0B6AC)),
        ],
      ]),
    );
    return open ? tile : Tooltip(message: m.name, child: tile);
  }
}

class _MemberAvatar extends StatefulWidget {
  const _MemberAvatar({required this.m});
  final _SeanceMember m;
  @override
  State<_MemberAvatar> createState() => _MemberAvatarState();
}

class _MemberAvatarState extends State<_MemberAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.m.speaking) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _MemberAvatar old) {
    super.didUpdateWidget(old);
    if (widget.m.speaking && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.m.speaking && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: m.tint,
              image: m.avatarUrl == null || m.avatarUrl!.isEmpty
                  ? null
                  : DecorationImage(
                      image: NetworkImage(
                        m.avatarUrl!.startsWith('http')
                            ? m.avatarUrl!
                            : '${Config.httpBase}${m.avatarUrl!}',
                      ),
                      fit: BoxFit.cover),
              border: Border.all(
                  color: m.speaking
                      ? const Color(0xFFE8A13C)
                      : const Color(0x2EF3E4CF),
                  width: 2),
              boxShadow: m.speaking
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE8A13C)
                            .withValues(alpha: 0.55 * (1 - _pulse.value)),
                        spreadRadius: 7 * _pulse.value,
                      ),
                    ]
                  : null,
            ),
            child: (m.avatarUrl != null && m.avatarUrl!.isNotEmpty)
                ? null
                : Text(m.initials,
                    style: TextStyle(
                      fontFamily: GoogleFonts.martianMono().fontFamily,
                      fontSize: 12,
                      color: const Color(0xFFF3E4CF),
                      fontWeight: FontWeight.w600,
                    )),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: m.role == _SeanceRole.away
                    ? const Color(0xFF6B6560)
                    : const Color(0xFF4ADE80),
                border: Border.all(color: const Color(0xFF0D0C0B), width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Controls ──────────────────────────────────────────────────────────────────

// Mic toggle + mic-picker arrow — visually grouped as one compound control.
class _MicButtonGroup extends StatelessWidget {
  const _MicButtonGroup({
    required this.muted,
    required this.onToggle,
    required this.onPickMic,
  });
  final bool muted;
  final VoidCallback onToggle;
  final VoidCallback onPickMic;

  @override
  Widget build(BuildContext context) {
    final fg = muted ? const Color(0xFF1B1210) : const Color(0xBFF3E4CF);
    final bg = muted ? const Color(0xFFE8A13C) : Colors.transparent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      height: 56,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    muted ? Icons.mic_off_outlined : Icons.mic_none_outlined,
                    size: 18,
                    color: fg,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    muted ? 'UNMUTE' : 'MUTE',
                    style: TextStyle(
                      fontFamily: GoogleFonts.martianMono().fontFamily,
                      fontSize: 9,
                      letterSpacing: 1.08,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 32,
            color: fg.withValues(alpha: 0.2),
          ),
          GestureDetector(
            onTap: onPickMic,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: fg.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active
        ? const Color(0xFF1B1210)
        : const Color(0xBFF3E4CF);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minWidth: 76),
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE8A13C) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontFamily: GoogleFonts.martianMono().fontFamily,
                    fontSize: 9,
                    letterSpacing: 1.08,
                    color: fg)),
          ],
        ),
      ),
    );
  }
}

// ── LIVE chip ─────────────────────────────────────────────────────────────────

class _LiveChip extends StatefulWidget {
  const _LiveChip();
  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4ADE80),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4ADE80)
                        .withValues(alpha: 0.5 * (1 - _c.value)),
                    spreadRadius: 8 * _c.value,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('LIVE',
              style: TextStyle(
                fontFamily: GoogleFonts.martianMono().fontFamily,
                fontSize: 9,
                color: const Color(0xFF7FE0A0),
                letterSpacing: 2.0,
              )),
        ],
      );
}
