// auth_service.dart — Handles registration, login, token refresh, and secure JWT storage; defines typed exceptions so callers can show appropriate UI without parsing raw error strings.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' show ClientException;
import '../config.dart';

class AuthResult {
  final String userId;
  final String username;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final String? roomKey;
  final List<String> friendIds;

  const AuthResult({
    required this.userId,
    required this.username,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    this.roomKey,
    this.friendIds = const [],
  });
}

class AuthService {
  static String get _base => Config.httpBase;

  static const _timeout = Duration(seconds: 10);
  static const _storage = FlutterSecureStorage();

  static const _kAccessToken  = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kUserId       = 'user_id';

  Future<({AuthResult result, String accessToken, String refreshToken})> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(_timeout);

      Map<String, dynamic> body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } on FormatException {
        throw const AuthException('Server is unreachable. Please try again shortly.');
      }
      if (res.statusCode == 403) {
        if ((body['code'] as String?) == 'email_not_verified') {
          throw const EmailNotVerifiedException();
        }
        throw AuthException(body['error'] as String? ?? 'Forbidden');
      }
      if (res.statusCode != 200) {
        throw AuthException(body['error'] as String? ?? 'Login failed');
      }
      return (
        result: _resultFromBody(body),
        accessToken: body['accessToken'] as String,
        refreshToken: body['refreshToken'] as String,
      );
    } on AuthException {
      rethrow;
    } on SocketException {
      throw const AuthException('Cannot reach server. Is it running?');
    } on ClientException {
      throw const AuthException('Cannot reach server. Is it running?');
    } on TimeoutException {
      throw const AuthException('Server took too long to respond.');
    } catch (e) {
      throw AuthException('Login error: $e');
    }
  }

  // Returns the backend's confirmation message (e.g. "Check your email…").
  // Throws AuthException on failure.
  Future<String> register({
    required String username,
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
          'displayName': displayName,
        }),
      ).timeout(_timeout);

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 201) {
        throw AuthException(body['error'] as String? ?? 'Registration failed');
      }
      return body['message'] as String? ?? 'Account created. Check your email to verify.';
    } on AuthException {
      rethrow;
    } on SocketException {
      throw const AuthException('Cannot reach server. Is it running?');
    } on ClientException {
      throw const AuthException('Cannot reach server. Is it running?');
    } on TimeoutException {
      throw const AuthException('Server took too long to respond.');
    } catch (e) {
      throw AuthException('Registration error: $e');
    }
  }

  // Always resolves without throwing, backend never reveals whether the email exists.
  Future<void> forgotPassword(String email) async {
    try {
      await http.post(
        Uri.parse('$_base/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(_timeout);
    } catch (_) {}
  }

  Future<void> resendVerification(String email) async {
    try {
      await http.post(
        Uri.parse('$_base/auth/resend-verification'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(_timeout);
    } catch (_) {}
  }

  Future<String?> refreshAccessToken(String refreshToken) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      ).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['accessToken'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout(String refreshToken) async {
    try {
      await http.post(
        Uri.parse('$_base/auth/logout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      ).timeout(_timeout);
    } catch (_) {}
  }

  Future<void> storeSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
  }) async {
    await _storage.write(key: _kAccessToken,  value: accessToken);
    await _storage.write(key: _kRefreshToken, value: refreshToken);
    await _storage.write(key: _kUserId,       value: userId);
  }

  Future<({String accessToken, String refreshToken, String userId})?> getStoredSession() async {
    final accessToken  = await _storage.read(key: _kAccessToken);
    final refreshToken = await _storage.read(key: _kRefreshToken);
    final userId       = await _storage.read(key: _kUserId);
    if (accessToken == null || refreshToken == null || userId == null) return null;
    return (accessToken: accessToken, refreshToken: refreshToken, userId: userId);
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kUserId);
  }

  static AuthResult _resultFromBody(Map<String, dynamic> body) {
    final u = body['user'] as Map<String, dynamic>? ?? body;
    return AuthResult(
      userId:      u['id']          as String,
      username:    u['username']    as String,
      email:       u['email']       as String? ?? '',
      displayName: u['displayName'] as String? ?? u['username'] as String,
      avatarUrl:   u['avatarUrl']   as String?,
      roomKey:     u['roomKey']     as String?,
      friendIds:   (u['friendIds'] as List? ?? []).cast<String>(),
    );
  }
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

// Thrown when the user registered successfully but needs email verification.
// Carries the message from the backend to display to the user.
class RegistrationPendingException extends AuthException {
  const RegistrationPendingException(super.message);
}

// Thrown when login is blocked because the email is not yet verified.
class EmailNotVerifiedException extends AuthException {
  const EmailNotVerifiedException()
      : super('Please verify your email before logging in.');
}
