import 'dart:io';

/// Backend endpoints. Defaults reach a backend on the dev machine from the
/// Android emulator (10.0.2.2) or iOS simulator (localhost). For a physical
/// phone on the same Wi-Fi: flutter run --dart-define=RADIAN_HOST=192.168.x.x
class AppConfig {
  static const _host = String.fromEnvironment('RADIAN_HOST');
  static const _apiUrl = String.fromEnvironment('API_URL');
  static const _ingestUrl = String.fromEnvironment('INGEST_URL');

  static String get host => _host.isNotEmpty ? _host : (Platform.isAndroid ? '10.0.2.2' : 'localhost');

  static String get apiUrl => _apiUrl.isNotEmpty ? _apiUrl : 'http://$host:8080';

  static String get ingestUrl => _ingestUrl.isNotEmpty ? _ingestUrl : 'ws://$host:8081/v1/telemetry/ws';
}
