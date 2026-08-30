import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/config/app_config.dart';
import 'app/integrations/native_map_configuration.dart';
import 'app/storage/app_storage.dart';
import 'features/preferences/data/mobility_preferences_repository.dart';
import 'features/voice/data/voice_preferences_repository.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final sharedPreferences = await SharedPreferences.getInstance();
  const nativeMapConfiguration = NativeMapConfiguration();
  final nativeMapAvailable = await nativeMapConfiguration.isAvailable();
  AppConfig.configureNativeGoogleMapsApiKey(
    await nativeMapConfiguration.webServiceApiKey(),
  );

  runApp(
    ProviderScope(
      overrides: [
        appStorageProvider.overrideWithValue(
          SharedPreferencesAppStorage(sharedPreferences),
        ),
        mobilityPreferencesRepositoryProvider.overrideWithValue(
          MobilityPreferencesRepository(sharedPreferences),
        ),
        voicePreferencesRepositoryProvider.overrideWithValue(
          VoicePreferencesRepository(sharedPreferences),
        ),
        nativeMapAvailableProvider.overrideWithValue(nativeMapAvailable),
      ],
      child: const MobilityAiApp(),
    ),
  );
}
