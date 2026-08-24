# Mobility AI

Flutter mobile application for a voice-first mobility companion. The primary
loop is listen → clarify → check trusted tools → recommend → confirm → guide →
observe → adapt. Maps and the camera support the companion

## Current setup

- Flutter 3.41.4 / Dart 3.11.1
- Android and iOS platforms
- Firebase project: `ai-mobility-assistant-capstone`
- Android package: `com.aimobility.ai_mobility_assistant`
- iOS bundle: `com.aimobility.aiMobilityAssistant`
- Minimum iOS version: 15.0

## Run locally

```sh
flutter pub get
flutter run
```

### Credentials and backend

Do not commit service keys. Use a platform-restricted Maps rendering key:

- Android: provide `GOOGLE_MAPS_API_KEY` as a Gradle property or environment
  variable.
- iOS: copy `ios/Flutter/Secrets.xcconfig.example` to
  `ios/Flutter/Secrets.xcconfig` and add an iOS app-restricted key.

Production Places, Routes, and Gemini traffic uses `COMPANION_BACKEND_URL` and
sends the signed-in Firebase ID token as a bearer token. The expected backend
contract is documented in `docs/APP_BUILD_PLAN.md`. Direct prototype access can
be supplied with Dart defines, but must not be used for a distributed build:

```sh
flutter run \
  --dart-define=COMPANION_BACKEND_URL=https://your-backend.example
```

For a short-lived local prototype only:

```sh
flutter run \
  --dart-define=GOOGLE_MAPS_WEB_SERVICE_API_KEY=YOUR_RESTRICTED_DEV_KEY \
  --dart-define=GEMINI_API_KEY=YOUR_DEV_KEY
```

### Look Ahead model and licensing

`ultralytics_yolo` downloads the official nano detection model on first use.
The Ultralytics package/model distribution terms (AGPL-3.0 or enterprise
license) must be resolved before distribution. The stock COCO model is only a
pipeline proof and is not a mobility hazard model.

## Quality checks

```sh
flutter analyze
flutter test
```

Physical-device release gates include TalkBack/VoiceOver, 200% text, denied
permissions, GPS loss, audio interruptions, low/mid/high-range YOLO profiling,
and supervised mobility field testing. A passing unit test does not validate
camera guidance or pedestrian safety.

## Refresh Firebase configuration

Install FlutterFire once if it is unavailable:

```sh
dart pub global activate flutterfire_cli
```

Then regenerate the platform configuration:

```sh
flutterfire configure --project=ai-mobility-assistant-capstone --platforms=android,ios
```

The local proposal and build roadmap are stored in `docs/`. That directory is
intentionally ignored by Git.
