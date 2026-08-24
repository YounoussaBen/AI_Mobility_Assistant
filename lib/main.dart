import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'features/preferences/data/mobility_preferences_repository.dart';
import 'features/voice/data/voice_preferences_repository.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final sharedPreferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        mobilityPreferencesRepositoryProvider.overrideWithValue(
          MobilityPreferencesRepository(sharedPreferences),
        ),
        voicePreferencesRepositoryProvider.overrideWithValue(
          VoicePreferencesRepository(sharedPreferences),
        ),
      ],
      child: const MobilityAiApp(),
    ),
  );
}
