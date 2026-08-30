import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reports whether the host app configured the native Google Maps renderer.
///
/// Google Maps on iOS raises an Objective-C exception when a platform view is
/// created without first providing an API key. Checking through the host
/// channel lets Flutter show a useful non-map journey surface instead.
class NativeMapConfiguration {
  const NativeMapConfiguration();

  static const _channel = MethodChannel('ai_mobility/map_configuration');

  static bool get requiresHostPreflight =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<bool> isAvailable() async {
    if (!requiresHostPreflight) return true;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<String?> webServiceApiKey() async {
    if (!requiresHostPreflight) return null;
    try {
      final value = await _channel.invokeMethod<String>('webServiceApiKey');
      return value?.trim().isNotEmpty == true ? value!.trim() : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// Defaults to the safest platform behavior and is replaced during app boot.
/// Tests and previews can override it without invoking a native platform view.
final nativeMapAvailableProvider = Provider<bool>(
  (ref) => !NativeMapConfiguration.requiresHostPreflight,
);
