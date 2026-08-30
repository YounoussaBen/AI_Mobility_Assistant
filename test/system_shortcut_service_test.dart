import 'package:ai_mobility_assistant/app/integrations/system_shortcut_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ai_mobility/system_shortcuts');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('emits the pending shortcut returned by the mobile host', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getInitialShortcut');
          return 'lens';
        });

    final service = SystemShortcutService();
    addTearDown(service.dispose);
    final firstAction = service.actions.first;

    await service.initialize();

    expect(await firstAction, SystemShortcutAction.lens);
  });
}
