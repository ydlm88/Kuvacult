import 'dart:convert';
import 'package:http/http.dart' as http;

class UpdateService {
  static const _currentVersion = '0.4.2';
  static const _repo = 'ydlm88/Kuvacult';

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
      return clean != _currentVersion ? latest : null;
    } catch (_) {
      return null;
    }
  }
}
