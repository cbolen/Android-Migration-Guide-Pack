# DataWedge Intent API — Quick Reference

DataWedge is the primary barcode/RFID integration for Zebra devices. Scan data is delivered to your app via broadcast intents — no camera or scanning code required in your app.

Full documentation: https://techdocs.zebra.com/datawedge/latest/guide/api/

---

## Receiving Scan Data

### BroadcastReceiver
```kotlin
class ScanReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == SCAN_ACTION) {
            val data = intent.getStringExtra("com.symbol.datawedge.data_string") ?: return
            val symbology = intent.getStringExtra("com.symbol.datawedge.label_type")
            val timestamp = intent.getStringExtra("com.symbol.datawedge.decode_time_stamp")
            // handle result
        }
    }
    companion object {
        const val SCAN_ACTION = "com.zebra.myapp.ACTION" // must match DataWedge profile intent action
    }
}
```

### Register / Unregister in Activity or Fragment
```kotlin
private val scanReceiver = ScanReceiver()

override fun onResume() {
    super.onResume()
    val filter = IntentFilter(ScanReceiver.SCAN_ACTION)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        registerReceiver(scanReceiver, filter, RECEIVER_NOT_EXPORTED)
    } else {
        registerReceiver(scanReceiver, filter)
    }
}

override fun onPause() {
    super.onPause()
    unregisterReceiver(scanReceiver)
}
```

---

## Sending DataWedge API Commands

All DataWedge API commands use the same action string. The command is determined by the extra key.

```kotlin
fun sendDataWedgeIntent(context: Context, extraKey: String, extraValue: Any) {
    Intent("com.symbol.datawedge.api.ACTION").also { intent ->
        when (extraValue) {
            is String -> intent.putExtra(extraKey, extraValue)
            is Bundle -> intent.putExtra(extraKey, extraValue)
            is Boolean -> intent.putExtra(extraKey, extraValue)
        }
        context.sendBroadcast(intent)
    }
}
```

---

## Common Commands

### Soft Scan Trigger
```kotlin
// Start scan
sendDataWedgeIntent(context, "com.symbol.datawedge.api.SOFT_SCAN_TRIGGER", "START_SCANNING")

// Stop scan
sendDataWedgeIntent(context, "com.symbol.datawedge.api.SOFT_SCAN_TRIGGER", "STOP_SCANNING")

// Toggle
sendDataWedgeIntent(context, "com.symbol.datawedge.api.SOFT_SCAN_TRIGGER", "TOGGLE_SCANNING")
```

### Enable / Disable DataWedge
```kotlin
sendDataWedgeIntent(context, "com.symbol.datawedge.api.ENABLE_DATAWEDGE", true)
sendDataWedgeIntent(context, "com.symbol.datawedge.api.ENABLE_DATAWEDGE", false)
```

### Switch Profile
```kotlin
sendDataWedgeIntent(context, "com.symbol.datawedge.api.SWITCH_TO_PROFILE", "MyAppProfile")
```

### Create / Configure Profile via SET_CONFIG
```kotlin
fun createDataWedgeProfile(context: Context, profileName: String, intentAction: String) {
    val profileConfig = Bundle().apply {
        putString("PROFILE_NAME", profileName)
        putString("PROFILE_ENABLED", "true")
        putString("CONFIG_MODE", "CREATE_IF_NOT_EXIST")

        // Associate with this app
        val appConfig = Bundle().apply {
            putString("PACKAGE_NAME", context.packageName)
            putStringArray("ACTIVITY_LIST", arrayOf("*"))
        }
        putParcelableArray("APP_LIST", arrayOf(appConfig))

        // Intent output plugin
        val intentPlugin = Bundle().apply {
            putString("PLUGIN_NAME", "INTENT")
            putString("RESET_CONFIG", "true")
            putBundle("PARAM_LIST", Bundle().apply {
                putString("intent_output_enabled", "true")
                putString("intent_action", intentAction)
                putString("intent_delivery", "2") // broadcast
            })
        }

        // Barcode plugin
        val barcodePlugin = Bundle().apply {
            putString("PLUGIN_NAME", "BARCODE")
            putString("RESET_CONFIG", "true")
            putBundle("PARAM_LIST", Bundle().apply {
                putString("scanner_selection", "auto")
                putString("scanner_input_enabled", "true")
            })
        }

        putParcelableArray("PLUGIN_CONFIG", arrayOf(intentPlugin, barcodePlugin))
    }

    sendDataWedgeIntent(context, "com.symbol.datawedge.api.SET_CONFIG", profileConfig)
}
```

---

## Receiving API Results

```kotlin
class DataWedgeResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "com.symbol.datawedge.api.RESULT_ACTION") return

        val command = intent.getStringExtra("com.symbol.datawedge.api.COMMAND") ?: return
        val result = intent.getStringExtra("com.symbol.datawedge.api.RESULT")
        val info = intent.getBundleExtra("com.symbol.datawedge.api.RESULT_INFO")

        if (result == "FAILURE") {
            val code = info?.getString("RESULT_CODE")
            Log.e("DataWedge", "Command $command failed: $code")
        }
    }
}

// Register for result notifications
sendDataWedgeIntent(context,
    "com.symbol.datawedge.api.REGISTER_FOR_NOTIFICATION",
    Bundle().apply {
        putString("com.symbol.datawedge.api.APPLICATION_NAME", context.packageName)
        putString("com.symbol.datawedge.api.NOTIFICATION_TYPE", "SCANNER_STATUS")
    }
)
```

---

## Common Extras Reference

| Extra Key | Type | Description |
|---|---|---|
| `com.symbol.datawedge.data_string` | String | Decoded barcode data |
| `com.symbol.datawedge.label_type` | String | Symbology (e.g. `LABEL-TYPE-CODE128`) |
| `com.symbol.datawedge.decode_time_stamp` | String | Decode timestamp |
| `com.symbol.datawedge.source` | String | `scanner`, `simulscan`, `msr` |
| `com.symbol.datawedge.data_length` | Int | Length of decoded data |

---

## Android 13+ Receiver Registration Note

When targeting API 33+, `registerReceiver` requires an export flag:
```kotlin
// For intents only from your own app or DataWedge (not exported to other apps)
registerReceiver(receiver, filter, RECEIVER_NOT_EXPORTED)

// Only if the receiver must accept broadcasts from other apps
registerReceiver(receiver, filter, RECEIVER_EXPORTED)
```
DataWedge broadcasts come from a system service — use `RECEIVER_NOT_EXPORTED` for scan receivers.