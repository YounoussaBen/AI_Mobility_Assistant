import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SystemShortcutAction { talk, guidance, lens }

class SystemShortcutService {
  static const _channel = MethodChannel('ai_mobility/system_shortcuts');

  final _actions = StreamController<SystemShortcutAction>.broadcast();
  bool _initialized = false;

  Stream<SystemShortcutAction> get actions => _actions.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shortcut') {
        _emit(call.arguments as String?);
      }
    });
    try {
      final initial = await _channel.invokeMethod<String>('getInitialShortcut');
      _emit(initial);
    } on MissingPluginException {
      // Desktop, web, and widget tests do not install the mobile host channel.
    } on PlatformException {
      // The app remains fully usable when the host cannot expose shortcuts.
    }
  }

  void _emit(String? raw) {
    final action = switch (raw) {
      'talk' => SystemShortcutAction.talk,
      'guidance' => SystemShortcutAction.guidance,
      'lens' => SystemShortcutAction.lens,
      _ => null,
    };
    if (action != null && !_actions.isClosed) _actions.add(action);
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _actions.close();
  }
}

final systemShortcutServiceProvider = Provider<SystemShortcutService>((ref) {
  final service = SystemShortcutService();
  ref.onDispose(service.dispose);
  return service;
});
