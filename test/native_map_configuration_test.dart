import 'package:ai_mobility_assistant/app/config/app_config.dart';
import 'package:ai_mobility_assistant/app/integrations/native_map_configuration.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ai_mobility/map_configuration');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    AppConfig.configureNativeGoogleMapsApiKey(null);
  });

  test('iOS map preflight returns the native configuration state', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'isAvailable');
          return true;
        });

    expect(await const NativeMapConfiguration().isAvailable(), isTrue);
  });

  test(
    'iOS map preflight fails closed when the host channel is absent',
    () async {
      expect(await const NativeMapConfiguration().isAvailable(), isFalse);
    },
  );

  test('native Maps key can configure prototype web services', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'webServiceApiKey') return 'local-test-key';
          return null;
        });

    final key = await const NativeMapConfiguration().webServiceApiKey();
    AppConfig.configureNativeGoogleMapsApiKey(key);

    expect(AppConfig.googleMapsWebServiceApiKey, 'local-test-key');
  });
}
