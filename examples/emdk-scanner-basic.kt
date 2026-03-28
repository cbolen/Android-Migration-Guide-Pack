/**
 * EMDK basic scanner setup.
 *
 * Use EMDK when DataWedge is insufficient — e.g., direct scanner control,
 * custom decode params, or when DataWedge is not available.
 *
 * For most new development, prefer DataWedge (see datawedge-receiver.kt).
 *
 * Requires: com.symbol.emdk in build.gradle
 */

import android.os.Bundle
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import com.symbol.emdk.EMDKManager
import com.symbol.emdk.EMDKManager.EMDKListener
import com.symbol.emdk.EMDKManager.FEATURE_TYPE
import com.symbol.emdk.EMDKResults
import com.symbol.emdk.barcode.BarcodeManager
import com.symbol.emdk.barcode.ScanDataCollection
import com.symbol.emdk.barcode.Scanner
import com.symbol.emdk.barcode.Scanner.DataListener
import com.symbol.emdk.barcode.Scanner.StatusListener
import com.symbol.emdk.barcode.ScannerException
import com.symbol.emdk.barcode.StatusData

class EmdkScannerActivity : AppCompatActivity(), EMDKListener, DataListener, StatusListener {

    private var emdkManager: EMDKManager? = null
    private var barcodeManager: BarcodeManager? = null
    private var scanner: Scanner? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val results = EMDKManager.getEMDKManager(applicationContext, this)
        if (results.statusCode != EMDKResults.STATUS_CODE.SUCCESS) {
            Log.e(TAG, "EMDKManager init failed: ${results.statusCode}")
        }
    }

    // ---- EMDKListener -------------------------------------------------------

    override fun onOpened(manager: EMDKManager) {
        emdkManager = manager
        initScanner()
    }

    override fun onClosed() {
        releaseScanner()
        emdkManager = null
    }

    // ---- Scanner lifecycle --------------------------------------------------

    private fun initScanner() {
        barcodeManager = emdkManager?.getInstance(FEATURE_TYPE.BARCODE) as? BarcodeManager
        scanner = barcodeManager?.getDevice(BarcodeManager.DeviceIdentifier.DEFAULT)
        scanner?.apply {
            addDataListener(this@EmdkScannerActivity)
            addStatusListener(this@EmdkScannerActivity)
            try {
                enable()
                triggerType = Scanner.TriggerType.HARD
                read()
            } catch (e: ScannerException) {
                Log.e(TAG, "Scanner enable failed: ${e.message}")
            }
        }
    }

    private fun releaseScanner() {
        try {
            scanner?.apply {
                removeDataListener(this@EmdkScannerActivity)
                removeStatusListener(this@EmdkScannerActivity)
                cancelRead()
                disable()
                release()
            }
        } catch (e: ScannerException) {
            Log.e(TAG, "Scanner release error: ${e.message}")
        }
        scanner = null
        emdkManager?.release(FEATURE_TYPE.BARCODE)
        barcodeManager = null
    }

    // ---- DataListener -------------------------------------------------------

    override fun onData(scanDataCollection: ScanDataCollection?) {
        if (scanDataCollection?.result != ScanDataCollection.ScanDataCollection.SUCCESS) return
        scanDataCollection.scanData.forEach { data ->
            val barcode = data.data
            val symbology = data.labelType.toString()
            runOnUiThread { handleScan(barcode, symbology) }
        }
        // Re-arm for next scan
        try { scanner?.read() } catch (e: ScannerException) { Log.e(TAG, "read() failed: ${e.message}") }
    }

    // ---- StatusListener -----------------------------------------------------

    override fun onStatus(statusData: StatusData?) {
        val state = statusData?.state
        Log.d(TAG, "Scanner status: $state")
    }

    // ---- Activity lifecycle -------------------------------------------------

    override fun onPause() {
        super.onPause()
        try { scanner?.disable() } catch (e: ScannerException) { Log.e(TAG, "disable failed") }
    }

    override fun onResume() {
        super.onResume()
        try {
            scanner?.enable()
            scanner?.read()
        } catch (e: ScannerException) {
            Log.e(TAG, "re-enable failed: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        releaseScanner()
        emdkManager?.release()
        emdkManager = null
    }

    private fun handleScan(data: String, symbology: String) {
        // Process scan result on main thread
    }

    companion object {
        private const val TAG = "EmdkScanner"
    }
}