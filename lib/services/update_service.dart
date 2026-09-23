import 'dart:convert';
import 'package:http/http.dart' as http;

class UpdateService {
  static const _currentVersion = '0.6';
  static const _repo = 'ydlm88/Kuvacult';

  static bool _isNewer(String remote, String current) {
    final r = remote.split('.').map(int.tryParse).toList();
    final c = current.split('.').map(int.tryParse).toList();
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? (r[i] ?? 0) : 0;
      final cv = i < c.length ? (c[i] ?? 0) : 0;
      if (rv > cv) return true;
      if (rv < cv) return false;
    }
    return false;
  }

  static Future<String?> checkForUpdate() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (res.statusCode != 200) return null;
      final latest = json.decode(res.body)['tag_name'] as String?;
      if (latest == null) return null;
      final clean = latest.replaceFirst('v', '');
      return _isNewer(clean, _currentVersion) ? latest : null;
    } catch (_) {
      return null;
    }
  }
}
