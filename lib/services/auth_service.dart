import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

const _kDomain    = 'dev-wdn5ybqovbac1hkc.us.auth0.com';
const _kClientId  = 'LZSv9ZIB3V4Jork3OJb7VRNuoYpEDnIq';
const _kScheme    = 'com.example.marquee';

// Auth0 Dashboard → Allowed Callback URLs must include: http://localhost:4823
// Auth0 Dashboard → Allowed Logout URLs must include:   http://localhost:4823
const _kDesktopPort     = 4823;
const _kDesktopRedirect = 'http://localhost:$_kDesktopPort';

/// Platform-agnostic auth result — decouples app logic from auth0_flutter's Credentials type.
class AuthResult {
  final String sub;
  final String name;
  final String? nickname;
  final String? email;
  const AuthResult({
    required this.sub,
    required this.name,
    this.nickname,
    this.email,
  });
}

class AuthService {
  final _auth0 = Auth0(_kDomain, _kClientId);

  // auth0_flutter doesn't support Windows or Linux — use PKCE flow there instead.
  bool get _isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux);

  Future<AuthResult> login() async {
    if (_isDesktop) return _desktopLogin();
    final creds = await _auth0
        .webAuthentication(scheme: _kScheme)
        .login(parameters: {'prompt': 'select_account'});
    return _fromCredentials(creds);
  }

  Future<void> logout() async {
    if (_isDesktop) return; // desktop sessions are in-memory only for now
    try {
      await _auth0.webAuthentication(scheme: _kScheme).logout();
    } catch (e) {
      debugPrint('Auth0 logout: $e');
    }
  }

  Future<AuthResult?> getStoredCredentials() async {
    if (_isDesktop) return null; // no persistent token store on desktop yet
    try {
      if (!await _auth0.credentialsManager.hasValidCredentials()) return null;
      return _fromCredentials(await _auth0.credentialsManager.credentials());
    } catch (_) {
      return null;
    }
  }

  Future<void> clearStoredCredentials() async {
    if (_isDesktop) return;
    try {
      await _auth0.credentialsManager.clearCredentials();
    } catch (_) {}
  }

  // ── Desktop PKCE flow (Windows / Linux) ──────────────────────────────────────
  // flutter_web_auth_2 opens the system browser and intercepts the localhost
  // redirect on port _kDesktopPort via a short-lived local HTTP server.

  Future<AuthResult> _desktopLogin() async {
    final verifier  = _generateVerifier();
    final challenge = _generateChallenge(verifier);

    final authUri = Uri.https(_kDomain, '/authorize', {
      'client_id':             _kClientId,
      'response_type':         'code',
      'redirect_uri':          _kDesktopRedirect,
      'scope':                 'openid profile email offline_access',
      'code_challenge':        challenge,
      'code_challenge_method': 'S256',
      'prompt':                'select_account',
    });

    // callbackUrlScheme must be the full http://localhost:{port} URL in v4 server mode.
    // useWebview: false opens Auth0 in the system browser (not an embedded webview),
    // then captures the redirect via a short-lived local HTTP server on _kDesktopPort.
    final result = await FlutterWebAuth2.authenticate(
      url: authUri.toString(),
      callbackUrlScheme: _kDesktopRedirect,
      options: const FlutterWebAuth2Options(useWebview: false),
    );

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null) throw Exception('No authorisation code returned');

    final tokenRes = await http.post(
      Uri.https(_kDomain, '/oauth/token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'grant_type':    'authorization_code',
        'client_id':     _kClientId,
        'code_verifier': verifier,
        'code':          code,
        'redirect_uri':  _kDesktopRedirect,
      }),
    );

    if (tokenRes.statusCode != 200) {
      throw Exception('Token exchange failed (${tokenRes.statusCode})');
    }

    final tokens = jsonDecode(tokenRes.body) as Map<String, dynamic>;
    final claims = _decodeJwt(tokens['id_token'] as String);

    return AuthResult(
      sub:      claims['sub'] as String,
      name:     (claims['name'] ?? claims['sub']) as String,
      nickname: claims['nickname'] as String?,
      email:    claims['email'] as String?,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  static AuthResult _fromCredentials(Credentials c) => AuthResult(
        sub:      c.user.sub,
        name:     c.user.name ?? c.user.sub,
        nickname: c.user.nickname,
        email:    c.user.email,
      );

  static String _generateVerifier() {
    final rng = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => rng.nextInt(256)))
        .replaceAll('=', '');
  }

  static String _generateChallenge(String verifier) => base64Url
      .encode(sha256.convert(utf8.encode(verifier)).bytes)
      .replaceAll('=', '');

  static Map<String, dynamic> _decodeJwt(String token) {
    final payload = token.split('.')[1];
    return jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(payload))),
    ) as Map<String, dynamic>;
  }
}
