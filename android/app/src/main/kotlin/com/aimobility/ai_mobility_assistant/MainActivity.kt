package com.aimobility.ai_mobility_assistant

import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "ai_mobility/system_shortcuts"
    private val mapConfigurationChannelName = "ai_mobility/map_configuration"
    private var shortcutChannel: MethodChannel? = null
    private var pendingShortcut: String? = null
    private var dartIsReadyForShortcuts = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingShortcut = shortcutFromIntent(intent)
        shortcutChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "getInitialShortcut") {
                    dartIsReadyForShortcuts = true
                    result.success(pendingShortcut)
                    pendingShortcut = null
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            mapConfigurationChannelName,
        ).setMethodCallHandler { call, result ->
            val mapsApiKey = mapsApiKey()
            when (call.method) {
                "isAvailable" -> result.success(mapsApiKey != null)
                "webServiceApiKey" -> result.success(mapsApiKey)
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val shortcut = shortcutFromIntent(intent) ?: return
        if (dartIsReadyForShortcuts) {
            shortcutChannel?.invokeMethod("shortcut", shortcut)
        } else {
            pendingShortcut = shortcut
        }
    }

    private fun shortcutFromIntent(intent: Intent?): String? {
        val value = intent?.data?.pathSegments?.firstOrNull()
        return value?.takeIf { it == "talk" || it == "guidance" || it == "lens" }
    }

    private fun mapsApiKey(): String? {
        val applicationInfo = packageManager.getApplicationInfo(
            packageName,
            PackageManager.GET_META_DATA,
        )
        return applicationInfo.metaData
            ?.getString("com.google.android.geo.API_KEY")
            ?.trim()
            ?.takeIf { it.isNotEmpty() && !it.startsWith("${'$'}{") }
    }
}
