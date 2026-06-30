// config.dart — Single source of truth for the backend host and protocol scheme.
// Flip _https to false and update _prodHost for local development — all services read from here.
class Config {
  static const String _prodHost = 'api.kuvacult.com';
  static const bool _https = true;

  static String get httpBase => '${_https ? 'https' : 'http'}://$_prodHost';
  static String get wsBase   => '${_https ? 'wss'  : 'ws' }://$_prodHost';
}
