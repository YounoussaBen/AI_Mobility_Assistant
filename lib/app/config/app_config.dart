abstract final class AppConfig {
  /// Prototype-only web-service credential.
  ///
  /// Production builds must leave this empty and use the authenticated
  /// companion backend for Places and Routes. It is deliberately separate
  /// from the platform-restricted key used to render Google Maps.
  static const _googleMapsWebServiceApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_WEB_SERVICE_API_KEY',
  );
  static String _nativeGoogleMapsApiKey = '';

  static String get googleMapsWebServiceApiKey =>
      _googleMapsWebServiceApiKey.isNotEmpty
      ? _googleMapsWebServiceApiKey
      : _nativeGoogleMapsApiKey;

  static void configureNativeGoogleMapsApiKey(String? value) {
    _nativeGoogleMapsApiKey = value?.trim() ?? '';
  }

  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const companionBackendUrl = String.fromEnvironment(
    'COMPANION_BACKEND_URL',
  );

  static const geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );
}
