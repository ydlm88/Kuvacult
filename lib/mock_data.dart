import 'package:flutter/material.dart';
import 'models.dart';

// ─── Members ───────────────────────────────────────────────────────────────────
// Placeholder member list used by avatar widgets and activity display.
// TODO(backend): Replace with real user lookups from your MongoDB users collection.
// GET /users/:id — return Member data for avatar rendering
final Map<String, Member> kMembers = {
  'mia':   const Member(id: 'mia',   name: 'Mia',   initial: 'M', avatarBg: Color(0xFFF6C453)),
  'leo':   const Member(id: 'leo',   name: 'Leo',   initial: 'L', avatarBg: Color(0xFF7AB9F2)),
  'ruby':  const Member(id: 'ruby',  name: 'Ruby',  initial: 'R', avatarBg: Color(0xFFE98AA8)),
  'guest': const Member(id: 'guest', name: 'Guest', initial: 'G', avatarBg: Color(0xFF5A5A5A)),
};

// ─── Streaming services ────────────────────────────────────────────────────────
// Static reference data for streaming service badge display.
// TODO(backend): Optionally fetch from a /streaming-services endpoint if the list
// becomes dynamic (e.g. regional availability, new services added).
final Map<String, StreamingService> kStreams = {
  'netflix': const StreamingService(id: 'netflix', name: 'Netflix',  abbr: 'N',   bg: Color(0xFFE50914), fg: Colors.white),
  'max':     const StreamingService(id: 'max',     name: 'Max',      abbr: 'Max', bg: Color(0xFF002BE7), fg: Colors.white),
  'prime':   const StreamingService(id: 'prime',   name: 'Prime',    abbr: 'P',   bg: Color(0xFF00A8E1), fg: Colors.white),
  'apple':   const StreamingService(id: 'apple',   name: 'Apple TV', abbr: 'tv+', bg: Color(0xFF000000), fg: Colors.white),
  'hulu':    const StreamingService(id: 'hulu',    name: 'Hulu',     abbr: 'H',   bg: Color(0xFF1CE783), fg: Colors.black),
  'disney':  const StreamingService(id: 'disney',  name: 'Disney+',  abbr: 'D+',  bg: Color(0xFF113CCF), fg: Colors.white),
  'mubi':    const StreamingService(id: 'mubi',    name: 'Mubi',     abbr: 'mu',  bg: Color(0xFF0A0A0A), fg: Colors.white),
};
