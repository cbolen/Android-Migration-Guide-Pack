/**
 * DataWedge scan result receiver boilerplate.
 *
 * Prerequisites:
 * - A DataWedge profile must exist with:
 *     - Intent output plugin enabled
 *     - Intent action set to SCAN_ACTION (below)
 *     - Intent delivery: Broadcast intent
 *     - App association: your package name
 *
 * Usage: register in onResume(), unregister in onPause()
 */

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.appcompat.app.AppCompatActivity

// ---- Receiver ---------------------------------------------------------------

class ScanReceiver(private val onScan: (data: String, symbology: String) -> Unit) : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != SCAN_ACTION) return

        val data = intent.getStringExtra("com.symbol.datawedge.data_string") ?: return
        val symbology = intent.getStringExtra("com.symbol.datawedge.label_type") ?: "UNKNOWN"

        onScan(data, symbology)
    }

    companion object {
        // Must match the Intent Action configured in your DataWedge profile
        const val SCAN_ACTION = "com.zebra.myapp.ACTION"
    }
}

// ---- Activity registration --------------------------------------------------

class MainActivity : AppCompatActivity() {

    private val scanReceiver = ScanReceiver { data, symbology ->
        handleScanResult(data, symbology)
    }

    override fun onResume() {
        super.onResume()
        val filter = IntentFilter(ScanReceiver.SCAN_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // API 33+: must declare export flag
            // Use RECEIVER_NOT_EXPORTED — DataWedge is a system service, not a third-party app
            registerReceiver(scanReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(scanReceiver, filter)
        }
    }

    override fun onPause() {
        super.onPause()
        unregisterReceiver(scanReceiver)
    }

    private fun handleScanResult(data: String, symbology: String) {
        // Process scanned data
    }
}

// ---- ViewModel with Flow ----------------------------------------------------

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

class ScanViewModel : androidx.lifecycle.ViewModel() {

    private val _scanResults = MutableSharedFlow<ScanResult>()
    val scanResults: SharedFlow<ScanResult> = _scanResults

    fun onScanReceived(data: String, symbology: String) {
        viewModelScope.launch {
            _scanResults.emit(ScanResult(data, symbology))
        }
    }
}

data class ScanResult(val data: String, val symbology: String)