import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let shortcutChannelName = "ai_mobility/system_shortcuts"
  private var shortcutChannel: FlutterMethodChannel?
  private var pendingShortcut: String?
  private var dartIsReadyForShortcuts = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let mapsKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String,
      !mapsKey.isEmpty,
      !mapsKey.hasPrefix("$(")
    {
      GMSServices.provideAPIKey(mapsKey)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    shortcutChannel = FlutterMethodChannel(
      name: shortcutChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    shortcutChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getInitialShortcut" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.dartIsReadyForShortcuts = true
      result(self?.pendingShortcut)
      self?.pendingShortcut = nil
    }
  }

  override func application(
    _ application: UIApplication,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(handleShortcut(shortcutItem))
  }

  @discardableResult
  func handleShortcut(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
    let action: String
    switch shortcutItem.type {
    case "ai.mobility.talk":
      action = "talk"
    case "ai.mobility.guidance":
      action = "guidance"
    case "ai.mobility.lens":
      action = "lens"
    default:
      return false
    }

    if dartIsReadyForShortcuts {
      shortcutChannel?.invokeMethod("shortcut", arguments: action)
    } else {
      pendingShortcut = action
    }
    return true
  }
}
