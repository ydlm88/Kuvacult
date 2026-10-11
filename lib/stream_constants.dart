// stream_constants.dart — Static lookup table mapping service IDs to badge colors
import 'package:flutter/material.dart';
import 'models.dart';

final Map<String, StreamingService> kStreams = {
  'netflix': const StreamingService(id: 'netflix', name: 'Netflix',  abbr: 'N',   bg: Color(0xFFE50914), fg: Colors.white),
  'max':     const StreamingService(id: 'max',     name: 'Max',      abbr: 'Max', bg: Color(0xFF002BE7), fg: Colors.white),
  'prime':   const StreamingService(id: 'prime',   name: 'Prime',    abbr: 'P',   bg: Color(0xFF00A8E1), fg: Colors.white),
  'apple':   const StreamingService(id: 'apple',   name: 'Apple TV', abbr: 'tv+', bg: Color(0xFF000000), fg: Colors.white),
  'hulu':    const StreamingService(id: 'hulu',    name: 'Hulu',     abbr: 'H',   bg: Color(0xFF1CE783), fg: Colors.black),
  'disney':  const StreamingService(id: 'disney',  name: 'Disney+',  abbr: 'D+',  bg: Color(0xFF113CCF), fg: Colors.white),
  'mubi':    const StreamingService(id: 'mubi',    name: 'Mubi',     abbr: 'mu',  bg: Color(0xFF0A0A0A), fg: Colors.white),
};
