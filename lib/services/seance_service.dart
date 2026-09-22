// seance_service.dart — LiveKit room connection for Séance.
// Host joins with mic; screen share is started manually via toggleScreenShare().
// Viewers join muted with a mic track so they can unmute to speak.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show desktopCapturer, SourceType, DesktopCapturerSource, ThumbnailSize;
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class SeanceParticipant {
  final String identity;
  final String? name;
  final bool isMuted;
  final String? avatarUrl;
  const SeanceParticipant({
    required this.identity,
    required this.name,
    required this.isMuted,
    this.avatarUrl,
  });
}

class SeanceService extends ChangeNotifier {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  bool _isHost = false;
  bool _micMuted = false;
  bool _screenAudioMuted = false;
  bool _localScreenAudioMuted = false;
  LocalVideoTrack? _screenTrack;
  LocalAudioTrack? _micTrack;
  LocalAudioTrack? _screenAudioTrack;
  LocalTrackPublication<LocalVideoTrack>? _screenPublication;
  bool _remoteEnded = false;
  bool _voluntaryDisconnect = false;
  String? _hostIdentity;
  String? _currentMicId;
  MediaDevice? _currentOutputDevice;

  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  bool get isHost => _isHost;
  bool get micMuted => _micMuted;
  bool get screenAudioMuted => _screenAudioMuted;
  bool get localScreenAudioMuted => _localScreenAudioMuted;
  bool get isSharing => _screenTrack != null;
  bool get hasScreenAudio => _screenAudioTrack != null;
  bool get remoteEnded => _remoteEnded;
  String? get currentMicId => _currentMicId;
  MediaDevice? get currentOutputDevice => _currentOutputDevice;

  void signalRemoteEnd() {
    _remoteEnded = true;
    notifyListeners();
  }

  VideoTrack? get remoteVideoTrack {
    if (_room == null) return null;
    for (final p in _room!.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        if (pub.subscribed && pub.track != null) return pub.track;
      }
    }
    return null;
  }

  LocalVideoTrack? get localScreenTrack => _screenTrack;

  List<SeanceParticipant> get viewers {
    if (_room == null) return [];
    return _room!.remoteParticipants.values.map((p) {
      // Only the mic track signals "muted" state — ignore screen share audio.
      final micPub = p.audioTrackPublications
          .where((pub) => pub.source == TrackSource.microphone)
          .firstOrNull;
      final muted = micPub?.muted ?? false;
      String? avatarUrl;
      if (p.metadata?.isNotEmpty == true) {
        try {
          final meta = jsonDecode(p.metadata!) as Map<String, dynamic>;
          avatarUrl = meta['avatarUrl'] as String?;
        } catch (_) {}
      }
      return SeanceParticipant(
        identity: p.identity,
        name: p.name,
        isMuted: muted,
        avatarUrl: avatarUrl,
      );
    }).toList();
  }

  Future<void> startAsHost(String livekitHost, String token) async {
    _isHost = true;
    await _connect(livekitHost, token);
    await _initAudioDevices();
    _micTrack = await LocalAudioTrack.create(AudioCaptureOptions(deviceId: _currentMicId));
    await _room!.localParticipant!.publishAudioTrack(_micTrack!);
    try { await WakelockPlus.enable(); } catch (_) {}
    notifyListeners();
  }

  Future<void> joinAsViewer(
    String livekitHost,
    String token, {
    String? hostIdentity,
  }) async {
    _isHost = false;
    _hostIdentity = hostIdentity;
    await _connect(livekitHost, token);
    await _initAudioDevices();
    _micTrack = await LocalAudioTrack.create(AudioCaptureOptions(deviceId: _currentMicId));
    await _room!.localParticipant!.publishAudioTrack(_micTrack!);
    _micMuted = true;
    await _micTrack!.mute();
    try { await WakelockPlus.enable(); } catch (_) {}
    notifyListeners();
  }

  /// Detects and selects the system default mic and output on join.
  Future<void> _initAudioDevices() async {
    try {
      final all = await Hardware.instance.enumerateDevices();
      final inputs = all.where((d) => d.kind == 'audioinput').toList();
      final outputs = all.where((d) => d.kind == 'audiooutput').toList();
      if (inputs.isNotEmpty) _currentMicId = inputs.first.deviceId;
      if (outputs.isNotEmpty) {
        _currentOutputDevice = outputs.first;
        await Hardware.instance.selectAudioOutput(outputs.first);
      }
    } catch (_) {}
  }

  /// Returns desktop window/screen sources. Returns null on mobile (use default share).
  Future<List<DesktopCapturerSource>?> getDesktopSources() async {
    if (!_isDesktop) return null;
    try {
      return await desktopCapturer.getSources(
        types: [SourceType.Screen, SourceType.Window],
        thumbnailSize: ThumbnailSize(150, 150),
      );
    } catch (_) {
      return null;
    }
  }

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> toggleScreenShare({String? sourceId}) async {
    if (_screenTrack != null) {
      // ── Stop sharing ───────────────────────────────────────────────────────
      final track = _screenTrack!;
      final audioTrack = _screenAudioTrack;
      final pub = _screenPublication;
      _screenTrack = null;
      _screenAudioTrack = null;
      _screenPublication = null;
      _screenAudioMuted = false;

      if (_room?.localParticipant != null) {
        // Unpublish screen audio (so viewers get a clean TrackUnpublishedEvent)
        if (audioTrack != null) {
          final audioSids = _room!.localParticipant!.audioTrackPublications
              .where((p) => p.source == TrackSource.screenShareAudio)
              .map((p) => p.sid)
              .toList();
          for (final sid in audioSids) {
            try { await _room!.localParticipant!.removePublishedTrack(sid); } catch (_) {}
          }
        }
        // Unpublish the video track via its stored publication SID
        if (pub != null) {
          try { await _room!.localParticipant!.removePublishedTrack(pub.sid); } catch (_) {}
        }
      }
      await audioTrack?.stop();
      await track.stop();
    } else {
      // ── Start sharing ──────────────────────────────────────────────────────
      final captureOptions = ScreenShareCaptureOptions(
        useiOSBroadcastExtension: false,
        maxFrameRate: 60,
        sourceId: sourceId,
        captureScreenAudio: true,
      );

      // Try to capture screen + system audio together; fall back to video-only.
      try {
        final tracks =
            await LocalVideoTrack.createScreenShareTracksWithAudio(captureOptions);
        for (final t in tracks) {
          if (t is LocalVideoTrack) {
            _screenTrack = t;
          } else if (t is LocalAudioTrack) {
            _screenAudioTrack = t;
          }
        }
      } catch (_) {
        _screenTrack = await LocalVideoTrack.createScreenShareTrack(captureOptions);
      }

      if (_screenTrack != null) {
        _screenPublication = await _room!.localParticipant!.publishVideoTrack(
          _screenTrack!,
          publishOptions: const VideoPublishOptions(
            simulcast: false,
            videoEncoding: VideoEncoding(maxBitrate: 6000000, maxFramerate: 60),
          ),
        );
      }
      if (_screenAudioTrack != null) {
        await _room!.localParticipant!.publishAudioTrack(
          _screenAudioTrack!,
          publishOptions: const AudioPublishOptions(name: 'screenAudio'),
        );
      }
    }
    notifyListeners();
  }

  /// Mutes/unmutes the system audio captured alongside screen share.
  /// Uses stopOnMute=false to avoid stopping the shared display media stream,
  /// which would freeze or drop screen share on some platforms.
  Future<void> toggleScreenAudio() async {
    if (_screenAudioTrack == null) return;
    _screenAudioMuted = !_screenAudioMuted;
    if (_screenAudioMuted) {
      await _screenAudioTrack!.mute(stopOnMute: false);
    } else {
      await _screenAudioTrack!.unmute(stopOnMute: false);
    }
    notifyListeners();
  }

  /// Mutes/unmutes the host's screen share audio locally — viewer-side only.
  /// Uses enable/disable on the remote MediaStreamTrack so audio stops decoding
  /// without unsubscribing from the track (which would require re-negotiation).
  Future<void> toggleLocalScreenAudio() async {
    if (_room == null) return;
    _localScreenAudioMuted = !_localScreenAudioMuted;
    for (final p in _room!.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        if (pub.source == TrackSource.screenShareAudio && pub.track != null) {
          if (_localScreenAudioMuted) {
            await pub.track!.disable();
          } else {
            await pub.track!.enable();
          }
        }
      }
    }
    notifyListeners();
  }

  Future<List<MediaDevice>> availableMics() async {
    final all = await Hardware.instance.enumerateDevices();
    return all.where((d) => d.kind == 'audioinput').toList();
  }

  Future<List<MediaDevice>> availableOutputs() async {
    final all = await Hardware.instance.enumerateDevices();
    return all.where((d) => d.kind == 'audiooutput').toList();
  }

  Future<void> switchMic(String deviceId) async {
    if (_micTrack == null) return;
    await _micTrack!.restartTrack(AudioCaptureOptions(deviceId: deviceId));
    _currentMicId = deviceId;
    notifyListeners();
  }

  Future<void> switchOutput(MediaDevice device) async {
    await Hardware.instance.selectAudioOutput(device);
    _currentOutputDevice = device;
    notifyListeners();
  }

  Future<void> toggleMic() async {
    if (_micTrack == null) return;
    _micMuted = !_micMuted;
    if (_micMuted) {
      await _micTrack!.mute();
    } else {
      await _micTrack!.unmute();
    }
    notifyListeners();
  }

  Future<void> _connect(String livekitHost, String token) async {
    _room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioPublishOptions: AudioPublishOptions(name: 'mic'),
      ),
    );
    _listener = _room!.createListener();
    _listener!
      ..on<RoomConnectedEvent>((_) => notifyListeners())
      ..on<RoomDisconnectedEvent>((_) {
        if (!_isHost && !_voluntaryDisconnect) {
          _remoteEnded = true;
        }
        notifyListeners();
      })
      ..on<ParticipantConnectedEvent>((_) => notifyListeners())
      ..on<ParticipantDisconnectedEvent>((e) {
        // If the host disconnects from LiveKit, signal remote end to the viewer.
        // This is a fallback for when the seance_ended WS message is missed.
        if (!_isHost &&
            _hostIdentity != null &&
            e.participant.identity == _hostIdentity) {
          _remoteEnded = true;
        }
        notifyListeners();
      })
      ..on<TrackPublishedEvent>((_) => notifyListeners())
      ..on<TrackUnpublishedEvent>((_) => notifyListeners())
      ..on<TrackSubscribedEvent>((_) => notifyListeners())
      ..on<TrackUnsubscribedEvent>((_) => notifyListeners())
      ..on<TrackMutedEvent>((_) => notifyListeners())
      ..on<TrackUnmutedEvent>((_) => notifyListeners());
    await _room!.connect(livekitHost, token);
  }

  @override
  Future<void> dispose() async {
    _voluntaryDisconnect = true;
    _listener?.dispose();
    await _screenAudioTrack?.stop();
    await _screenTrack?.stop();
    await _micTrack?.stop();
    await _room?.disconnect();
    _room = null;
    _screenTrack = null;
    _screenAudioTrack = null;
    _screenPublication = null;
    _micTrack = null;
    try { await WakelockPlus.disable(); } catch (_) {}
    super.dispose();
  }
}
