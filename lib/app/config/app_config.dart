abstract final class AppConfig {
  static const googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyBbexUi3Xs7HMhxAsheMVYFeZ1vu1Xylzw',
  );

  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );
}
