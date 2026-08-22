# Mobility AI

Flutter mobile application for accessible route planning, transport comparison,
live journey guidance, hazard detection, and conversational assistance.

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

## Quality checks

```sh
flutter analyze
flutter test
```

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
