import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let shortcutChannelName = "ai_mobility/system_shortcuts"
  private let mapConfigurationChannelName = "ai_mobility/map_configuration"
  private var shortcutChannel: FlutterMethodChannel?
  private var mapConfigurationChannel: FlutterMethodChannel?
  private var pendingShortcut: String?
  private var dartIsReadyForShortcuts = false
  private var googleMapsIsConfigured = false
  private var googleMapsApiKey: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let rawMapsKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String
    {
      let mapsKey = rawMapsKey.trimmingCharacters(in: .whitespacesAndNewlines)
      if !mapsKey.isEmpty,
        !mapsKey.hasPrefix("$("),
        !mapsKey.contains("YOUR_IOS_RESTRICTED_MAPS_KEY")
      {
        googleMapsIsConfigured = GMSServices.provideAPIKey(mapsKey)
        googleMapsApiKey = googleMapsIsConfigured ? mapsKey : nil
      }
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
    mapConfigurationChannel = FlutterMethodChannel(
      name: mapConfigurationChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    mapConfigurationChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "isAvailable":
        result(self?.googleMapsIsConfigured ?? false)
      case "webServiceApiKey":
        result(self?.googleMapsApiKey)
      default:
        result(FlutterMethodNotImplemented)
      }
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
