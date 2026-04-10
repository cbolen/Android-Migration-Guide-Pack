# Migration Plan: InventoryApp targetSdk 30 → 35

**Generated**: 2026-04-09  
**Scanner**: migrate.log (12 FOUND, 10 VERIFY)  
**Source reviewed**: AndroidManifest.xml, all Kotlin files, app/build.gradle, build.gradle  
**Starting point**: targetSdk 30, compileSdk 30, minSdk 26, AGP 7.3.0, Java 1.8

---

## 1. BLOCKING ISSUES

Issues that cause install failure or runtime crash. Every item from migrate.log [FOUND] and [VERIFY] is accounted for below, along with additional issues discovered by cross-file analysis.

---

### B-1 — Install failure: missing `android:exported` on five manifest components  
**API level**: 31 | **File**: `app/src/main/AndroidManifest.xml`

All five components have `<intent-filter>` but no `android:exported` attribute. Apps targeting API 31+ will not install.

| Line | Component | Required value | Reason |
|------|-----------|----------------|--------|
| 32 | `MainActivity` | `exported="false"` | Custom action; only launched internally |
| 40 | `AddItemActivity` | `exported="false"` | Custom action; only launched internally |
| 52 | `ScanReceiver` | `exported="true"` | DataWedge is a separate system process; must be reachable from outside the app |
| 61 | `LowStockAlertReceiver` | `exported="false"` | Only receives PendingIntents created by this app |
| 68 | `StockCheckReceiver` | `exported="false"` | Only receives AlarmManager PendingIntents |

**Fix**: Add `android:exported` to each element as shown above.

---

### B-2 — Runtime crash: `PendingIntent` created with `flags = 0`  
**API level**: 31 | **Severity**: `IllegalArgumentException` at runtime

All four calls pass `0` as the flags argument. API 31+ requires `FLAG_IMMUTABLE` (for intents that do not need modification) or `FLAG_MUTABLE`.

| File | Line | Call | Fix |
|------|------|------|-----|
| `util/NotificationHelper.kt` | 57 | `PendingIntent.getBroadcast(context, 0, trampolineIntent, 0)` | Replace `0` with `PendingIntent.FLAG_IMMUTABLE` |
| `util/NotificationHelper.kt` | 78 | `PendingIntent.getActivity(context, 1, mainIntent, 0)` | Replace `0` with `PendingIntent.FLAG_IMMUTABLE` |
| `util/StockAlarmScheduler.kt` | 39 | `PendingIntent.getBroadcast(context, REQUEST_CODE, intent, 0)` | Replace `0` with `PendingIntent.FLAG_IMMUTABLE` |
| `util/StockAlarmScheduler.kt` | 64 | `PendingIntent.getBroadcast(context, REQUEST_CODE, intent, 0)` | Replace `0` with `PendingIntent.FLAG_IMMUTABLE` |

Use `PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT` if the intent extras change between calls.

---

### B-3 — Runtime crash: BouncyCastle provider removed  
**API level**: 31 | **Severity**: `NoSuchProviderException` at runtime  
**File**: `util/CryptoHelper.kt` lines 37, 52

Both `encrypt()` and `decrypt()` call `Cipher.getInstance(TRANSFORMATION, "BC")`. The `"BC"` BouncyCastle provider was removed from Android 12. The default JCA provider (Conscrypt) supports `AES/CBC/PKCS5Padding`.

**Fix**:  
```kotlin
// Before
val cipher = Cipher.getInstance(TRANSFORMATION, PROVIDER)  // PROVIDER = "BC"

// After
val cipher = Cipher.getInstance(TRANSFORMATION)
```

Remove the `PROVIDER` constant and all references to it.

---

### B-4 — Runtime crash: exact alarm without permission or guard  
**API level**: 31 | **Severity**: `SecurityException` at runtime  
**Files**: `AndroidManifest.xml` lines 11–12, `util/StockAlarmScheduler.kt` lines 53, 77

Two separate problems:

1. `SCHEDULE_EXACT_ALARM` permission is **missing from the manifest**. Without it, `setExactAndAllowWhileIdle()` throws `SecurityException` on API 31+.
2. `StockAlarmScheduler.scheduleDailyCheck()` calls `setExactAndAllowWhileIdle()` **without** a `canScheduleExactAlarms()` guard.
3. `StockCheckReceiver.onReceive()` at line 76 **also calls** `scheduleDailyCheck()` to reschedule — this second call has the same problem and will crash during the alarm callback.

**Fix**:

Add to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

Wrap the alarm call in `StockAlarmScheduler.scheduleDailyCheck()`:
```kotlin
val alarmManager = context.getSystemService(AlarmManager::class.java)
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
    // Redirect the user to the exact-alarm permission settings page
    val settingsIntent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(settingsIntent)
    return
}
alarmManager.setExactAndAllowWhileIdle(...)
```

---

### B-5 — Runtime crash / blocked: notification trampoline  
**API level**: 31 | **Severity**: notification tap silently does nothing  
**Files**: `util/NotificationHelper.kt` lines 48–57, `LowStockAlertReceiver.kt` lines 15–23

`NotificationHelper.showLowStockNotification()` builds a `PendingIntent` that fires `LowStockAlertReceiver`, which then calls `context.startActivity(launchIntent)`. Starting an Activity from a `BroadcastReceiver` triggered by a notification content-intent is blocked on API 31+ targeting API 31+.

**Fix**: Remove `LowStockAlertReceiver` entirely. Attach a `PendingIntent` targeting `MainActivity` directly as the notification's content intent:

```kotlin
// In NotificationHelper.showLowStockNotification():
val mainIntent = Intent(context, MainActivity::class.java).apply {
    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
}
val pendingIntent = PendingIntent.getActivity(
    context, 0, mainIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
)
```

Remove `LowStockAlertReceiver.kt` and its `<receiver>` entry in the manifest (line 61–65).

---

### B-6 — Runtime crash: `AsyncTask` removed  
**API level**: 33 | **Severity**: `NoClassDefFoundError` at runtime  
**File**: `data/InventoryRepository.kt` — five inner classes (lines 36, 43, 51, 59, 67)

`AsyncTask` was removed in API 33. All five tasks must be replaced with Kotlin coroutines.

**Fix**: Add `kotlinx-coroutines-android` to `app/build.gradle`, then replace each `AsyncTask` with a coroutine dispatched to `Dispatchers.IO`. Example for `FetchAllTask`:

```kotlin
fun getAllItems(callback: (List<InventoryItem>) -> Unit) {
    CoroutineScope(Dispatchers.IO).launch {
        val result = database.getAllItems()
        withContext(Dispatchers.Main) { callback(result) }
    }
}
```

Apply the same pattern to `findByBarcode`, `insertItem`, `updateItem`, and `checkLowStock`. Long-term, move these into a `ViewModel` with `viewModelScope`.

---

### B-7 — Runtime exception: `registerReceiver()` without export flag  
**API level**: 33 | **Severity**: `SecurityException` at runtime  
**File**: `MainActivity.kt` line 117

`registerReceiver(scanReceiver, filter)` is called without a flags argument. On API 33+ targeting API 33+, this throws an exception.

**Fix**:
```kotlin
// Replace the bare registerReceiver call with:
ContextCompat.registerReceiver(
    this, scanReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED
)
```

DataWedge sends explicitly targeted broadcasts (package-addressed), so `RECEIVER_NOT_EXPORTED` is safe — targeted broadcasts are delivered even to non-exported receivers.

---

### B-8 — Runtime crash: `ScanReceiver` in manifest has no no-arg constructor  
**API level**: all | **Severity**: `InstantiationException` if system tries to deliver to manifest receiver  
**Files**: `AndroidManifest.xml` line 52, `datawedge/ScanReceiver.kt` line 13

`ScanReceiver` takes a lambda in its primary constructor:
```kotlin
class ScanReceiver(private val onScanResult: (barcode: String, labelType: String) -> Unit)
```

Android requires manifest-declared `BroadcastReceiver` classes to have a public no-arg constructor. If the OS attempts to instantiate this class (e.g., on a broadcast while the app is backgrounded), it will throw `InstantiationException`.

The receiver is already registered dynamically in `MainActivity.setupScanReceiver()`, so the manifest entry is redundant. Scanning only occurs while the app is in the foreground anyway.

**Fix**: Remove the `ScanReceiver` `<receiver>` block from `AndroidManifest.xml` (lines 52–57). No other change is needed — the dynamic registration in `MainActivity` handles all scan results.

> Note: The manifest entry also lacks `android:exported` (covered by B-1), so removing it resolves both issues at once.

---

## 2. REQUIRED CHANGES

Issues that cause silent failure, permission denial, or visual regression.

---

### R-1 — Silent drop: `POST_NOTIFICATIONS` not declared and not requested at runtime  
**API level**: 33 | **File**: `AndroidManifest.xml` line 11, `util/NotificationHelper.kt` lines 71, 92

`NotificationManager.notify()` is called in two places without any prior runtime permission check. On API 33+, notifications are silently dropped unless `POST_NOTIFICATIONS` has been granted.

**Fix**:

1. Add to `AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
   ```

2. Request the permission at runtime before the first notification is shown. The appropriate place is `MainActivity.onCreate()` or before scheduling `StockAlarmScheduler`:
   ```kotlin
   if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
       notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
   }
   ```
   Use `registerForActivityResult(ActivityResultContracts.RequestPermission())` (not `requestPermissions`).

---

### R-2 — Silent revocation: `SCHEDULE_EXACT_ALARM` not re-checked in `onResume`  
**API level**: 34 | **File**: `SettingsActivity.kt` (no `onResume` override), `MainActivity.kt` (no `onResume` alarm check)

On API 34+, `SCHEDULE_EXACT_ALARM` is automatically revoked when the app is updated. The app never re-checks `canScheduleExactAlarms()` after the initial launch, so alarms silently stop firing after an update.

**Fix**: Add a check in `SettingsActivity.onResume()` (the screen with the notifications toggle):
```kotlin
override fun onResume() {
    super.onResume()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val am = getSystemService(AlarmManager::class.java)
        if (!am.canScheduleExactAlarms()) {
            // Disable the notifications switch UI and prompt the user
            switchNotifications.isChecked = false
            switchNotifications.isEnabled = false
            // Show a banner/snackbar directing user to Settings
        }
    }
}
```

---

### R-3 — Visual regression: no edge-to-edge inset handling  
**API level**: 35 (enforced) | **Files**: `MainActivity.kt` line 35, `AddItemActivity.kt` line 41, `ExportActivity.kt` line 31

On API 35, the system forces edge-to-edge rendering. Content will be drawn behind the status bar and navigation bar, clipping interactive elements.

`SettingsActivity` is **already correctly handled** — it calls `WindowCompat.setDecorFitsSystemWindows(window, false)` and applies `ViewCompat.setOnApplyWindowInsetsListener` with system bar insets. Apply the same pattern to the three remaining activities.

**Fix for each missing activity** (use SettingsActivity as the reference implementation):
```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    WindowCompat.setDecorFitsSystemWindows(window, false)
    setContentView(R.layout.activity_xyz)
    val content = findViewById<View>(android.R.id.content)
    ViewCompat.setOnApplyWindowInsetsListener(content) { view, insets ->
        val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
        view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
        insets
    }
}
```

---

### R-4 — Deprecated: `onBackPressed()` override  
**API level**: 33+ | **File**: `MainActivity.kt` line 154

`override fun onBackPressed()` is deprecated from API 33. The override is not enforced to compile, but the predictive-back gesture (API 34+) is opt-in via the manifest and requires `OnBackPressedCallback`.

**Fix**:
```kotlin
// Remove the onBackPressed() override. In onCreate(), add:
onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(enabled = true) {
    override fun handleOnBackPressed() {
        AlertDialog.Builder(this@MainActivity)
            .setTitle("Exit")
            .setMessage("Are you sure you want to exit the inventory app?")
            .setPositiveButton("Exit") { _, _ ->
                dwManager.disableScanning()
                finish()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
})
```

---

### R-5 — Deprecated: `startActivityForResult` / `onRequestPermissionsResult` / `onActivityResult`  
**API level**: varies (deprecated API 29–33) | **Files**: multiple

The scanner detected 13 call sites across 3 activities. These are all deprecated and should be replaced with `ActivityResultContracts`.

| File | Lines | Pattern | Replacement contract |
|------|-------|---------|----------------------|
| `MainActivity.kt` | 57, 65, 136 | `startActivityForResult(intent, code)` | `ActivityResultContracts.StartActivityForResult` |
| `MainActivity.kt` | 75–92 | `onActivityResult()` override | Remove; handle in `ActivityResultCallback` |
| `AddItemActivity.kt` | 68–72 | `ActivityCompat.requestPermissions(CAMERA)` | `ActivityResultContracts.RequestPermission` |
| `AddItemActivity.kt` | 83 | `startActivityForResult(galleryIntent)` | `ActivityResultContracts.PickVisualMedia` (Photo Picker) |
| `AddItemActivity.kt` | 96–110 | `onRequestPermissionsResult()` override | Remove; handle in `ActivityResultCallback` |
| `AddItemActivity.kt` | 114–130 | `onActivityResult()` override | Remove; handle in `ActivityResultCallback` |
| `AddItemActivity.kt` | 145 | `startActivityForResult(cameraIntent)` | `ActivityResultContracts.TakePicture` |
| `ExportActivity.kt` | 56–65 | `requestPermissions(WRITE_EXTERNAL_STORAGE)` | Remove entirely (permission no longer needed with `getExternalFilesDir`) |
| `ExportActivity.kt` | 71–85 | `onRequestPermissionsResult()` override | Remove entirely |

The `ACTION_PICK` + `MediaStore.Images.Media.EXTERNAL_CONTENT_URI` approach in `AddItemActivity` should be replaced with `PickVisualMedia` (API 19+ with the Photo Picker backport via `androidx.activity:activity-ktx:1.7+`).

---

### R-6 — Permission denied / data loss: storage APIs broken under scoped storage  
**API level**: 29+ (full enforcement) | **Files**: multiple

Three separate storage problems:

**R-6a — `Environment.getExternalStorageDirectory()` not writable** (API 29+):  
`StorageHelper.getExportDirectory()` line 22, `StorageHelper.getTempDirectory()` line 50, `ExportActivity.writeExportFile()` line 110.  
Fix: Replace with `context.getExternalFilesDir("exports")` / `context.cacheDir`. No permission required.

**R-6b — Hardcoded `/sdcard/` path** (not portable, not accessible under scoped storage):  
`StorageHelper.getPhotosDirectory()` line 36. Used by `AddItemActivity.launchCamera()` via `StorageHelper.getPhotoFile()`.  
Fix:
```kotlin
fun getPhotosDirectory(context: Context): File {
    return context.getExternalFilesDir(Environment.DIRECTORY_PICTURES)
        ?: context.filesDir  // fallback if external storage unavailable
}
```

**R-6c — `WRITE_EXTERNAL_STORAGE` gating blocks export unnecessarily** (API 29+):  
`ExportActivity.exportInventory()` lines 52–65 refuses to export if `WRITE_EXTERNAL_STORAGE` is not granted. This permission is ignored on API 29+ targets. The result: export is permanently blocked on any API 29+ device because the permission will never be granted.  
Fix: Remove the permission check from `exportInventory()` entirely. The `getExternalFilesDir()` path requires no permission.

---

### R-7 — Legacy storage permissions  
**API level**: 33 | **File**: `AndroidManifest.xml` lines 4–7

`READ_EXTERNAL_STORAGE` (line 5) is replaced by `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` / `READ_MEDIA_AUDIO` on API 33+.  
`WRITE_EXTERNAL_STORAGE` (line 7) is a no-op on API 29+ targets.

**Fix**: Replace with granular permissions and scope each to the appropriate API level:
```xml
<!-- Keep with maxSdkVersion for devices below API 33 -->
<uses-permission
    android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />

<!-- API 33+ granular media permissions — add only the types the app actually accesses -->
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />

<!-- WRITE_EXTERNAL_STORAGE: no-op on API 29+ but harmless to keep with maxSdkVersion -->
<uses-permission
    android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="28" />
```

The app only stores/reads photos (images) and CSV files (not media). Add `READ_MEDIA_IMAGES` only if the app needs to read gallery images beyond its own `getExternalFilesDir()` folder.

---

### R-8 — Deprecated: `Handler()` no-arg constructor  
**API level**: 30 | **File**: `SplashActivity.kt` line 42

`Handler()` without a `Looper` was deprecated in API 30 and will warn on API 30+ builds.

**Fix**:
```kotlin
Handler(Looper.getMainLooper()).postDelayed({ ... }, SPLASH_DELAY_MS)
```

Also note: the custom `SplashActivity` with a timed delay is the pre-API-31 pattern. Android 12+ provides a mandatory system splash screen. Consider migrating to `androidx.core:core-splashscreen` and removing this activity.

---

### R-9 — Deprecated: untyped `getParcelableExtra` call  
**API level**: 33 | **File**: `MainActivity.kt` line 202

The `getParcelableExtraCompat` inline extension function still calls the deprecated untyped `getParcelableExtra(key)`:
```kotlin
private inline fun <reified T : Parcelable> Intent.getParcelableExtraCompat(key: String): T? {
    @Suppress("DEPRECATION")
    return getParcelableExtra(key)  // ← deprecated on API 33+
}
```

**Fix**: Use the typed overload on API 33+:
```kotlin
private inline fun <reified T : Parcelable> Intent.getParcelableExtraCompat(key: String): T? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        getParcelableExtra(key, T::class.java)
    } else {
        @Suppress("DEPRECATION")
        getParcelableExtra(key)
    }
}
```

---

### R-10 — Build: stale build configuration  
**Files**: `app/build.gradle`, `build.gradle`

| Setting | Current | Target | Impact |
|---------|---------|--------|--------|
| `compileSdkVersion` | 30 | 35 | Cannot reference API 31–35 symbols |
| `targetSdkVersion` | 30 | 35 | Behavior changes from API 31–35 not activated |
| `JavaVersion.VERSION_1_8` | `sourceCompatibility` / `targetCompatibility` | `VERSION_17` | Required for AGP 8 and Kotlin 1.9+ |
| `jvmTarget` | `'1.8'` | `'17'` | Consistent with Java compat |
| `classpath "com.android.tools.build:gradle:7.3.0"` | 7.3.0 | 8.x | Required for compileSdk 35 |
| Gradle wrapper | pre-8.x | 8.x+ | Required for AGP 8 |
| `kotlin_version` | 1.7.10 | 1.9+ | Required for Kotlin coroutines stability |
| `androidx.core:core-ktx` | 1.6.0 | 1.13+ | Required for `ContextCompat.registerReceiver` |
| `androidx.appcompat:appcompat` | 1.3.1 | 1.7+ | Required for `OnBackPressedCallback`, API 35 compat |
| `com.google.android.material:material` | 1.4.0 | 1.12+ | Required for Material 3 and API 35 edge-to-edge |
| `androidx.recyclerview:recyclerview` | 1.2.0 | 1.3+ | Latest stable |
| `androidx.constraintlayout:constraintlayout` | 2.0.4 | 2.1+ | Latest stable |

**Add to `app/build.gradle` dependencies**:
```groovy
implementation 'org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3'
implementation 'androidx.activity:activity-ktx:1.9.0'
implementation 'androidx.lifecycle:lifecycle-runtime-ktx:2.8.0'
```

---

## 3. ZEBRA-SPECIFIC ISSUES

---

### Z-1 — `ScanReceiver` manifest entry: no-arg constructor + missing exported  
**Files**: `AndroidManifest.xml` lines 50–57, `datawedge/ScanReceiver.kt` line 13

The manifest declares `ScanReceiver` as a static receiver, but the class only has a primary constructor that requires a lambda callback. Android instantiates manifest receivers via reflection using a no-arg constructor — this will throw `InstantiationException` if the OS ever delivers a broadcast to the manifest entry.

Additionally, `ScanReceiver` listens for DataWedge broadcasts (`com.symbol.datawedge.api.RESULT_ACTION` and `com.example.inventoryapp.SCAN_RESULT`). DataWedge sends from a separate system process, so the manifest receiver would need `android:exported="true"` to receive them. Combined with B-8 above, this entry does nothing useful.

**Fix**: Remove the `<receiver android:name=".datawedge.ScanReceiver">` block from `AndroidManifest.xml` entirely. The dynamic registration in `MainActivity.setupScanReceiver()` handles all scan results while the app is in the foreground (which is the only time scanning is active). No manifest receiver is needed.

---

### Z-2 — `registerReceiver()` missing `RECEIVER_NOT_EXPORTED` flag  
**API level**: 33 | **File**: `MainActivity.kt` line 117

Covered by B-7 above. DataWedge delivers scan results as explicit broadcasts targeted at `com.example.inventoryapp`, so `RECEIVER_NOT_EXPORTED` is safe — package-targeted broadcasts bypass the export flag check.

**Important**: Do **not** use `RECEIVER_EXPORTED` here. Using `RECEIVER_EXPORTED` would allow any app on the device to inject fake scan results into the receiver.

---

### Z-3 — DataWedge `RESULT_ACTION` filter registered but silently dropped  
**File**: `MainActivity.kt` lines 107, 114–115; `datawedge/ScanReceiver.kt` line 28

`setupScanReceiver()` registers the receiver for both `com.symbol.datawedge.api.RESULT_ACTION` (DataWedge API response channel) and `com.example.inventoryapp.SCAN_RESULT` (scan data channel).

`ScanReceiver.onReceive()` returns early if `intent.action != ACTION_SCAN_RESULT`, so all `RESULT_ACTION` callbacks (profile creation confirmations, scanner enable/disable results) are silently ignored. This is acceptable for the current implementation, but means there is no feedback path to confirm that `createInventoryProfile()`, `enableScanning()`, and `disableScanning()` succeeded.

**No immediate fix required** — scanning functions correctly. Consider adding a separate `BroadcastReceiver` for `RESULT_ACTION` if operational feedback is needed.

---

### Z-4 — DataWedge profile configured correctly  
**File**: `datawedge/DataWedgeManager.kt`

`DataWedgeManager.createInventoryProfile()` uses `intent_delivery = "2"` (broadcast) which is the correct mode for receiving scan results when `RECEIVER_NOT_EXPORTED` is used. The profile associates all activities (`*`) in the package, enables common barcode symbologies (Code128, Code39, UPC-A, UPC-E, EAN-13, EAN-8, QR, DataMatrix), and disables keystroke output. This is correct for an enterprise inventory scanner use case.

**No changes needed** to `DataWedgeManager.kt` aside from the `registerReceiver()` flag fix in `MainActivity`.

---

### Z-5 — EMDK: not used  
**File**: no EMDK imports found in any source file

The app does not use EMDK directly. All barcode scanning goes through DataWedge. The `[OK] EMDK usage` result in migrate.log is correct. No EMDK changes required.

---

## 4. SUGGESTED PHASE ORDER

Apply changes in this order to isolate regressions at each Android version boundary.

---

### Phase 1 — Build infrastructure (prerequisite for all phases)

1. Upgrade Gradle wrapper to 8.x (`gradle/wrapper/gradle-wrapper.properties`)
2. Update AGP to 8.x in `build.gradle` classpath
3. Update `kotlin_version` to 1.9+
4. In `app/build.gradle`:
   - `compileSdkVersion 30` → `compileSdk 35`
   - `targetSdkVersion 30` → `targetSdk 35`
   - `JavaVersion.VERSION_1_8` → `JavaVersion.VERSION_17` (both `sourceCompatibility` and `targetCompatibility`)
   - `jvmTarget '1.8'` → `jvmTarget '17'`
5. Update all AndroidX dependencies to the versions in R-10
6. Add `kotlinx-coroutines-android`, `activity-ktx`, `lifecycle-runtime-ktx` dependencies
7. Verify the project builds (expect many lint/compilation errors — these are fixed in subsequent phases)

---

### Phase 2 — API 31: install failure and runtime crashes (highest priority)

Fixes that prevent the app from installing or running on Android 12+ devices.

1. **B-1**: Add `android:exported` to all 5 manifest components
2. **B-8**: Remove `ScanReceiver` from the manifest
3. **B-5**: Remove the notification trampoline — delete `LowStockAlertReceiver.kt`, remove its manifest entry, and update `NotificationHelper.showLowStockNotification()` to use a direct `PendingIntent` to `MainActivity`
4. **B-2**: Add `PendingIntent.FLAG_IMMUTABLE` to all 4 `PendingIntent` calls
5. **B-3**: Remove `"BC"` provider argument from both `CryptoHelper` methods
6. **B-4**: Add `SCHEDULE_EXACT_ALARM` to manifest; add `canScheduleExactAlarms()` guard in `StockAlarmScheduler.scheduleDailyCheck()` — this fix also covers the recursive reschedule in `StockCheckReceiver.onReceive()`

**Checkpoint**: Install and launch on an Android 12 emulator or device. Verify app installs, launches, and crypto operations work.

---

### Phase 3 — API 33: runtime exception and silent failures

1. **B-6**: Replace all 5 `AsyncTask` classes in `InventoryRepository` with Kotlin coroutines
2. **B-7 / Z-2**: Add `RECEIVER_NOT_EXPORTED` to `registerReceiver()` in `MainActivity`
3. **R-1**: Add `POST_NOTIFICATIONS` to manifest; add runtime permission request in `MainActivity.onCreate()`
4. **R-7**: Replace storage permissions in manifest (add `READ_MEDIA_IMAGES`, add `maxSdkVersion` guards)
5. **R-8**: Fix `Handler()` → `Handler(Looper.getMainLooper())` in `SplashActivity`
6. **R-9**: Update `getParcelableExtraCompat` to use the typed `getParcelableExtra(key, Class)` on API 33+

**Checkpoint**: Test on Android 13. Verify: low-stock notification appears, scan results are received, export works.

---

### Phase 4 — API 34: permission revocation

1. **R-2**: Add `canScheduleExactAlarms()` check in `SettingsActivity.onResume()` with UI feedback and re-enable flow

**Checkpoint**: On Android 14, manually revoke `SCHEDULE_EXACT_ALARM` in Settings → Apps and confirm the app handles the revocation gracefully.

---

### Phase 5 — API 35: visual and behavioral

1. **R-3**: Add edge-to-edge inset handling to `MainActivity`, `AddItemActivity`, and `ExportActivity` (model on the existing correct implementation in `SettingsActivity`)
2. **R-4**: Replace `onBackPressed()` with `OnBackPressedCallback` in `MainActivity`
3. **R-5**: Replace all `startActivityForResult` / `onActivityResult` / `onRequestPermissionsResult` usages with `ActivityResultContracts` in `MainActivity`, `AddItemActivity`, and `ExportActivity`
4. **R-6**: Fix all storage paths — replace `getExternalStorageDirectory()` and `/sdcard/` with `getExternalFilesDir()` / `cacheDir`; remove `WRITE_EXTERNAL_STORAGE` permission gating from `ExportActivity`

**Checkpoint**: Test on Android 15. Verify: layout is correct in both gesture and 3-button navigation modes; back-press dialog appears; camera capture and gallery pick work; CSV export succeeds.

---

## 5. TESTING CHECKLIST

For each issue, the test target, input action, and pass criteria are listed below.

---

### API 31 — Android 12

| ID | What to test | Device/level | Pass criteria |
|----|-------------|--------------|---------------|
| B-1 | Install the signed APK | API 31 device or emulator | App installs without `INSTALL_FAILED_MISSING_SPLIT` or `exported` rejection |
| B-2 | Tap the low-stock notification | API 31 | Notification tap opens `MainActivity`; no `IllegalArgumentException` in logcat |
| B-2 | Schedule daily alarm via Settings screen | API 31 | No crash; alarm appears in `adb shell dumpsys alarm` |
| B-3 | Export CSV (triggers `CryptoHelper`) | API 31 | CSV written to disk; no `NoSuchProviderException` in logcat |
| B-4 | Enable notifications in Settings → tap Save | API 31 | `canScheduleExactAlarms()` guard executes without crash; if permission missing, Settings intent fires |
| B-5 | Trigger low-stock alert (set threshold above current stock) | API 31 | Tapping notification opens `MainActivity` directly; no trampoline pattern in logcat |
| B-8 | Send `com.example.inventoryapp.SCAN_RESULT` broadcast via `adb` | API 31 | Broadcast arrives at dynamically registered receiver only; no `InstantiationException` |

---

### API 33 — Android 13

| ID | What to test | Device/level | Pass criteria |
|----|-------------|--------------|---------------|
| B-6 | Add item, load inventory list, trigger low-stock check | API 33 | All database operations complete; no `NoClassDefFoundError: AsyncTask` |
| B-7 / Z-2 | Launch `MainActivity` | API 33 | No `SecurityException` from `registerReceiver` in logcat |
| R-1 | First launch after fresh install | API 33 | `POST_NOTIFICATIONS` permission dialog appears |
| R-1 | Grant notification permission then trigger low stock | API 33 | Notification appears in notification shade |
| R-1 | Deny notification permission then trigger low stock | API 33 | No crash; notification silently skipped |
| R-7 | Access gallery from `AddItemActivity` | API 33 | `READ_MEDIA_IMAGES` granted or Photo Picker opens without permission prompt |
| R-8 | Launch `SplashActivity` | API 33 | Splash displays for 2 s then transitions; no deprecation exception |

---

### API 34 — Android 14

| ID | What to test | Device/level | Pass criteria |
|----|-------------|--------------|---------------|
| R-2 | Revoke `SCHEDULE_EXACT_ALARM` in Settings → Apps → Special access | API 34 | On returning to `SettingsActivity`, notifications switch is disabled or a prompt appears; no crash |
| R-2 | Re-grant `SCHEDULE_EXACT_ALARM` and toggle notifications on | API 34 | `StockAlarmScheduler.scheduleDailyCheck()` executes without exception |
| R-5 | Permission re-check on `onResume` | API 34 | No `SecurityException` from implicit intent or `registerReceiver` |

---

### API 35 — Android 15

| ID | What to test | Device/level | Pass criteria |
|----|-------------|--------------|---------------|
| R-3 | Open each activity in gesture navigation mode | API 35 | No content is hidden behind status bar or navigation bar; RecyclerView scrolls to the bottom row |
| R-3 | Rotate device in `AddItemActivity` | API 35 | Layout redraws correctly; no clipping |
| R-3 | Open each activity in 3-button navigation mode | API 35 | Bottom bar visible; buttons not obscured |
| R-4 | Swipe back from `MainActivity` | API 35 | Predictive-back swipe preview visible (if `android:enableOnBackInvokedCallback="true"` set in manifest); dialog appears on completion |
| R-5 | Take photo → save item | API 35 | Photo path stored; image displayed in `ImageView`; `TakePicture` contract used |
| R-5 | Pick from gallery → save item | API 35 | Image URI received; `PickVisualMedia` contract used; no `onActivityResult` warnings in logcat |
| R-6 | Export CSV | API 35 | CSV written to `getExternalFilesDir("exports")`; no `WRITE_EXTERNAL_STORAGE` dialog; file appears in Files app under `Android/data/com.example.inventoryapp` |
| R-6 | Take photo | API 35 | Photo saved to `getExternalFilesDir(DIRECTORY_PICTURES)`; FileProvider URI delivered to camera app |

---

### Zebra device — DataWedge

| ID | What to test | Device | Pass criteria |
|----|-------------|--------|---------------|
| Z-1/Z-2 | Scan a barcode with the hardware trigger | TC / MC / EC device running DataWedge | Scan result appears in `MainActivity` (matched item toast or `AddItemActivity` opened); no duplicate delivery |
| Z-2 | Confirm `RECEIVER_NOT_EXPORTED` does not block DataWedge delivery | Zebra device API 33+ | Scan result received; logcat shows no export-flag rejection |
| Z-4 | Open Settings → Reconfigure DataWedge Profile | Zebra device | Toast "DataWedge profile reconfigured"; subsequent scans still delivered correctly |
| Z-4 | Check DataWedge profile in DataWedge app after `createInventoryProfile()` | Zebra device | "InventoryApp" profile visible, intent output enabled, keystroke output disabled |
| General | Test on square-display Zebra device (WS50/WS501) if in scope | WS50 or WS501 | No layout clipping at corners; RecyclerView fully visible |

---

### Cross-cutting checks

| Check | Condition | Pass criteria |
|-------|-----------|---------------|
| Large font scale | System font at 200% | No text truncation in `item_row.xml`, `activity_main.xml`; quantity and location fields still readable |
| Notification on reboot | Reboot device after alarm scheduled | Low-stock alarm reschedules correctly on next app launch (PendingIntents cancelled on force-stop per API 35; verify boot behavior) |
| Crypto round-trip | Encrypt then decrypt a known payload | Decrypted bytes match original; no provider exception |
| Database thread safety | Rapid add-then-load operations | No `SQLiteDatabaseLockedException`; coroutine dispatching to `Dispatchers.IO` confirmed in logcat |
