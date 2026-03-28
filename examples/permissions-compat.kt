/**
 * Permission request patterns for Android 11–15.
 *
 * Uses ActivityResultContracts — replaces deprecated
 * onRequestPermissionsResult / requestPermissions.
 */

import android.Manifest
import android.content.pm.PackageManager.PERMISSION_GRANTED
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat

class PermissionsActivity : AppCompatActivity() {

    // ---- Camera -------------------------------------------------------------

    private val requestCamera = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) onCameraReady() else onCameraDenied()
    }

    fun requestCameraIfNeeded() {
        when {
            ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PERMISSION_GRANTED ->
                onCameraReady()
            shouldShowRequestPermissionRationale(Manifest.permission.CAMERA) ->
                showCameraRationale { requestCamera.launch(Manifest.permission.CAMERA) }
            else ->
                requestCamera.launch(Manifest.permission.CAMERA)
        }
    }

    // ---- Notifications (API 33+) --------------------------------------------

    private val requestNotifications = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (!granted) {
            // Notification features gracefully disabled — do not crash
        }
    }

    fun requestNotificationsIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PERMISSION_GRANTED) {
                requestNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        // API < 33: permission not required
    }

    // ---- Media (API 33+ granular, API 32 and below READ_EXTERNAL_STORAGE) ---

    private val requestMediaPermissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { results ->
        val canReadImages = results[Manifest.permission.READ_MEDIA_IMAGES] == true ||
                results[Manifest.permission.READ_EXTERNAL_STORAGE] == true
        if (canReadImages) onMediaAccessGranted()
    }

    fun requestMediaReadIfNeeded() {
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO
            )
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

        val alreadyGranted = permissions.all {
            ContextCompat.checkSelfPermission(this, it) == PERMISSION_GRANTED
        }

        if (!alreadyGranted) requestMediaPermissions.launch(permissions)
        else onMediaAccessGranted()
    }

    // ---- Location -----------------------------------------------------------

    private val requestLocation = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { results ->
        val fine = results[Manifest.permission.ACCESS_FINE_LOCATION] == true
        val coarse = results[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        if (fine || coarse) onLocationGranted()
    }

    fun requestLocationIfNeeded() {
        requestLocation.launch(arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ))
    }

    // Note: ACCESS_BACKGROUND_LOCATION must be requested SEPARATELY after
    // foreground location is granted — cannot be requested in the same call.

    // ---- Callbacks (implement as needed) ------------------------------------

    private fun onCameraReady() {}
    private fun onCameraDenied() {}
    private fun onMediaAccessGranted() {}
    private fun onLocationGranted() {}
    private fun showCameraRationale(onConfirm: () -> Unit) {}
}