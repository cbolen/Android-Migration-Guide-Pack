/**
 * DataWedge Intent API — common commands.
 *
 * All commands use action "com.symbol.datawedge.api.ACTION".
 * The specific command is set via the extra key.
 *
 * Full API reference: https://techdocs.zebra.com/datawedge/latest/guide/api/
 */

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log

object DataWedgeApi {

    private const val DW_ACTION = "com.symbol.datawedge.api.ACTION"
    private const val DW_RESULT_ACTION = "com.symbol.datawedge.api.RESULT_ACTION"

    // ---- Trigger ------------------------------------------------------------

    fun startScan(context: Context) = trigger(context, "START_SCANNING")
    fun stopScan(context: Context) = trigger(context, "STOP_SCANNING")
    fun toggleScan(context: Context) = trigger(context, "TOGGLE_SCANNING")

    private fun trigger(context: Context, value: String) {
        send(context, "com.symbol.datawedge.api.SOFT_SCAN_TRIGGER", value)
    }

    // ---- Enable / Disable ---------------------------------------------------

    fun enable(context: Context) = send(context, "com.symbol.datawedge.api.ENABLE_DATAWEDGE", true)
    fun disable(context: Context) = send(context, "com.symbol.datawedge.api.ENABLE_DATAWEDGE", false)

    // ---- Profile ------------------------------------------------------------

    fun switchProfile(context: Context, profileName: String) {
        send(context, "com.symbol.datawedge.api.SWITCH_TO_PROFILE", profileName)
    }

    /**
     * Create or update a DataWedge profile with intent output configured
     * to broadcast to [intentAction].
     */
    fun createProfile(context: Context, profileName: String, intentAction: String) {
        val config = Bundle().apply {
            putString("PROFILE_NAME", profileName)
            putString("PROFILE_ENABLED", "true")
            putString("CONFIG_MODE", "CREATE_IF_NOT_EXIST")

            putParcelableArray("APP_LIST", arrayOf(
                Bundle().apply {
                    putString("PACKAGE_NAME", context.packageName)
                    putStringArray("ACTIVITY_LIST", arrayOf("*"))
                }
            ))

            putParcelableArray("PLUGIN_CONFIG", arrayOf(
                Bundle().apply {  // Intent output
                    putString("PLUGIN_NAME", "INTENT")
                    putString("RESET_CONFIG", "true")
                    putBundle("PARAM_LIST", Bundle().apply {
                        putString("intent_output_enabled", "true")
                        putString("intent_action", intentAction)
                        putString("intent_delivery", "2") // broadcast
                    })
                },
                Bundle().apply {  // Barcode input
                    putString("PLUGIN_NAME", "BARCODE")
                    putString("RESET_CONFIG", "true")
                    putBundle("PARAM_LIST", Bundle().apply {
                        putString("scanner_selection", "auto")
                        putString("scanner_input_enabled", "true")
                    })
                }
            ))
        }
        send(context, "com.symbol.datawedge.api.SET_CONFIG", config)
    }

    // ---- Notifications ------------------------------------------------------

    fun registerForScannerStatus(context: Context) {
        send(context, "com.symbol.datawedge.api.REGISTER_FOR_NOTIFICATION",
            Bundle().apply {
                putString("com.symbol.datawedge.api.APPLICATION_NAME", context.packageName)
                putString("com.symbol.datawedge.api.NOTIFICATION_TYPE", "SCANNER_STATUS")
            }
        )
    }

    fun unregisterForScannerStatus(context: Context) {
        send(context, "com.symbol.datawedge.api.UNREGISTER_FOR_NOTIFICATION",
            Bundle().apply {
                putString("com.symbol.datawedge.api.APPLICATION_NAME", context.packageName)
                putString("com.symbol.datawedge.api.NOTIFICATION_TYPE", "SCANNER_STATUS")
            }
        )
    }

    // ---- Internal -----------------------------------------------------------

    private fun send(context: Context, key: String, value: String) {
        context.sendBroadcast(Intent(DW_ACTION).apply { putExtra(key, value) })
    }

    private fun send(context: Context, key: String, value: Boolean) {
        context.sendBroadcast(Intent(DW_ACTION).apply { putExtra(key, value) })
    }

    private fun send(context: Context, key: String, value: Bundle) {
        context.sendBroadcast(Intent(DW_ACTION).apply { putExtra(key, value) })
    }
}

// ---- Result receiver --------------------------------------------------------

import android.content.BroadcastReceiver

class DataWedgeResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "com.symbol.datawedge.api.RESULT_ACTION") return

        val command = intent.getStringExtra("com.symbol.datawedge.api.COMMAND") ?: return
        val result = intent.getStringExtra("com.symbol.datawedge.api.RESULT")
        val info = intent.getBundleExtra("com.symbol.datawedge.api.RESULT_INFO")

        if (result == "FAILURE") {
            val code = info?.getString("RESULT_CODE")
            Log.e("DataWedgeResult", "Command $command failed: $code")
        } else {
            Log.d("DataWedgeResult", "Command $command succeeded")
        }
    }
}