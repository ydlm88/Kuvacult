// config.dart — Single source of truth for the backend host and protocol scheme.
// Override at build time — never edit this file for environment changes:
//   flutter run --dart-define=API_HOST=localhost:3000 --dart-define=API_HTTPS=false
//   flutter run --dart-define=API_HOST=10.0.2.2:3000 --dart-define=API_HTTPS=false  (Android emulator)
class Config {
  static const String _host = String.fromEnvironment(
    'API_HOST',
    defaultValue: 'api.kuvacult.com',
  );
  static const bool _https = bool.fromEnvironment(
    'API_HTTPS',
    defaultValue: true,
  );

  static String get httpBase => '${_https ? 'https' : 'http'}://$_host';
  static String get wsBase   => '${_https ? 'wss'  : 'ws' }://$_host';
}
