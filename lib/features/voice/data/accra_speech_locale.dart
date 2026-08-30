import 'package:speech_to_text/speech_to_text.dart';

/// Uses Ghanaian English when the device recognizer exposes it, with stable
/// English fallbacks for devices that do not ship an en-GH speech model.
Future<String?> preferredAccraSpeechLocale(SpeechToText speech) async {
  try {
    final locales = await speech.locales();
    for (final preferred in const ['en_GH', 'en-GH', 'en_GB', 'en-GB']) {
      final match = locales.where((locale) => locale.localeId == preferred);
      if (match.isNotEmpty) return match.first.localeId;
    }
    final english = locales.where(
      (locale) => locale.localeId.toLowerCase().startsWith('en'),
    );
    return english.firstOrNull?.localeId;
  } catch (_) {
    return null;
  }
}
