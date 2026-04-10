# InventoryApp-Legacy — Phase 0 Migration Plan (Android 11 → Android 15)

> **Note**: This is the Phase 0 output from running the discovery prompt against the android-migration-sample app. The sample app was built to contain almost every possible issue — a real app will typically have a much smaller subset.

**Project**: `com.example.inventoryapp`
**Current**: `targetSdkVersion 30`, `compileSdkVersion 30`, Java 1.8
**Target**: `targetSdk 35`, `compileSdk 35`, Java 17
**Scan baseline**: `migrate.log` (14 FOUND, 8 VERIFY)
**Source reviewed**: AndroidManifest.xml, all Kotlin source files, app/build.gradle

---

## 1. BLOCKING ISSUES

These cause install failure or a runtime crash. Fix every item in this section before testing on any API 31+ device.

---

### BLK-01 — Missing `android:exported` on five manifest components
**API level**: 31 (install failure)
**Files**:
- `AndroidManifest.xml:32` — `.MainActivity` has `intent-filter`, `android:exported` absent
- `AndroidManifest.xml:40` — `.AddItemActivity` has `intent-filter`, `android:exported` absent
- `AndroidManifest.xml:52` — `.datawedge.ScanReceiver` has `intent-filter`, `android:exported` absent
- `AndroidManifest.xml:61` — `.LowStockAlertReceiver` has `intent-filter`, `android:exported` absent
- `AndroidManifest.xml:68` — `.util.StockCheckReceiver` has `intent-filter`, `android:exported` absent

**VERIFY result**: Confirmed missing on all five. `.SplashActivity` already has `android:exported="true"` and is correct.

**Fix**: Add `android:exported` to each component.
- `.MainActivity` — internal action, only started by this app: `android:exported="false"`
- `.AddItemActivity` — internal action: `android:exported="false"`
- `.datawedge.ScanReceiver` — must receive DataWedge broadcasts from the DataWedge system process: `android:exported="true"`
- `.LowStockAlertReceiver` — only receives intents from this app's `PendingIntent`; should be `android:exported="false"` (see also BLK-03)
- `.util.StockCheckReceiver` — only receives intents from this app's `AlarmManager` `PendingIntent`: `android:exported="false"`

---

### BLK-02 — `PendingIntent` created without `FLAG_IMMUTABLE`
**API level**: 31 (runtime crash — `IllegalArgumentException`)
**Files**:
- `util/NotificationHelper.kt:57` — `PendingIntent.getBroadcast(..., 0)` for trampoline intent
- `util/NotificationHelper.kt:78` — `PendingIntent.getActivity(..., 0)` for export-complete notification
- `util/StockAlarmScheduler.kt:39` — `PendingIntent.getBroadcast(..., 0)` for alarm scheduling
- `util/StockAlarmScheduler.kt:64` — `PendingIntent.getBroadcast(..., 0)` for alarm cancellation

**VERIFY result**: Confirmed — all four calls pass `0` as the flags argument. None include `FLAG_IMMUTABLE` or `FLAG_MUTABLE`.

**Fix**: Add `PendingIntent.FLAG_IMMUTABLE` to every call. None of these `PendingIntent`s need to be mutated by another app or by the system, so `FLAG_IMMUTABLE` is correct for all four. Example:
```kotlin
val pendingIntent = PendingIntent.getBroadcast(
    context, 0, trampolineIntent,
    PendingIntent.FLAG_IMMUTABLE
)
```

---

### BLK-03 — Notification trampoline (`LowStockAlertReceiver` calls `startActivity`)
**API level**: 31 (silent block — activity never launches when notification is tapped)
**Files**:
- `util/NotificationHelper.kt:52–65` — notification `contentIntent` targets `LowStockAlertReceiver`
- `LowStockAlertReceiver.kt:17–21` — receiver's `onReceive()` calls `context.startActivity()`

**FOUND in log**: Yes, both files flagged.

**Details**: `showLowStockNotification()` wraps `LowStockAlertReceiver` in a `PendingIntent.getBroadcast` and attaches it to the notification's `contentIntent`. When the notification is tapped on API 31+, the receiver fires but `startActivity()` is blocked by the OS — the user sees nothing happen. This is a two-file interaction the log identified structurally but did not trace the exact call chain through.

**Fix**: Remove `LowStockAlertReceiver` entirely. Replace the trampoline `PendingIntent` in `NotificationHelper.showLowStockNotification()` with a direct `PendingIntent.getActivity` targeting `MainActivity`:
```kotlin
val mainIntent = Intent(context, MainActivity::class.java).apply {
    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
}
val pendingIntent = PendingIntent.getActivity(
    context, 0, mainIntent, PendingIntent.FLAG_IMMUTABLE
)
```
Remove the `LowStockAlertReceiver` declaration from the manifest as well.

---

### BLK-04 — BouncyCastle provider removed
**API level**: 31 (runtime crash — `NoSuchProviderException`)
**File**: `util/CryptoHelper.kt:37, 52`

**FOUND in log**: Yes.

**Details**: Both `encrypt()` and `decrypt()` call `Cipher.getInstance("AES/CBC/PKCS5Padding", "BC")`. Android 12 removes the BouncyCastle implementations. The `PROVIDER = "BC"` constant is used in both methods.

**Fix**: Remove the second argument from both `Cipher.getInstance` calls:
```kotlin
val cipher = Cipher.getInstance(TRANSFORMATION) // default Conscrypt provider
```
Delete the `private const val PROVIDER = "BC"` constant; it is no longer referenced.

---

### BLK-05 — `setExactAndAllowWhileIdle()` without `SCHEDULE_EXACT_ALARM` permission
**API level**: 31 (runtime crash — `SecurityException`)
**File**: `util/StockAlarmScheduler.kt:53`

**VERIFY result (exact alarm guard)**: Confirmed absent. The comment in the file explicitly documents the missing guard. There is no `canScheduleExactAlarms()` check anywhere in `scheduleDailyCheck()` or in any `onResume()` override.

**Also**: `SCHEDULE_EXACT_ALARM` is not declared in `AndroidManifest.xml` (line 12 comment confirms this). Without the manifest declaration, the permission cannot be granted at all.

**Fix**:
1. Add to manifest: `<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />`
2. Guard the scheduling call:
```kotlin
val alarmManager = context.getSystemService(AlarmManager::class.java)
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
    context.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK
    })
    return
}
alarmManager.setExactAndAllowWhileIdle(...)
```

---

### BLK-06 — `AsyncTask` removed
**API level**: 33 (runtime crash — `NoClassDefFoundError`)
**File**: `data/InventoryRepository.kt:38, 46, 54, 62, 67`

**FOUND in log**: Yes — five `AsyncTask` subclasses: `FetchAllTask`, `FindByBarcodeTask`, `InsertItemTask`, `UpdateItemTask`, `CheckLowStockTask`.

**Fix**: Convert all five inner classes to Kotlin coroutines. `InventoryRepository` needs a `CoroutineScope`; the repository is created directly in activities so either pass a `ViewModel`-scoped `CoroutineScope` or introduce `ViewModel` classes. Minimal fix per task:
```kotlin
fun getAllItems(callback: (List<InventoryItem>) -> Unit) {
    CoroutineScope(Dispatchers.IO).launch {
        val result = database.getAllItems()
        withContext(Dispatchers.Main) { callback(result) }
    }
}
```
Preferred: introduce `InventoryViewModel` backed by `viewModelScope` and remove the callback pattern.

---

### BLK-07 — `Handler()` no-arg constructor removed
**API level**: 33 (runtime crash — constructor removed)
**File**: `SplashActivity.kt:42`

**FOUND in log**: Yes (mechanical fix available via `--fix`).

**Fix**: `Handler(Looper.getMainLooper()).postDelayed({...}, SPLASH_DELAY_MS)`

Note: see also REQD-04 — the custom `SplashActivity` pattern should be replaced with the Jetpack SplashScreen library, which eliminates this call entirely.

---

### BLK-08 — `onBackPressed()` override — enforced removal
**API level**: 35 (behavior break; `onBackPressed` is effectively dead code on API 35 with predictive back enforced)
**File**: `MainActivity.kt:154`

**FOUND in log**: Yes.

**Details**: The override shows an exit confirmation dialog. On API 35 with predictive back enforced, `onBackPressed()` may not be called, so the dialog never appears and the app exits silently.

**Fix**:
```kotlin
onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
    override fun handleOnBackPressed() {
        AlertDialog.Builder(this@MainActivity)
            .setTitle("Exit")
            .setMessage("Are you sure you want to exit?")
            .setPositiveButton("Exit") { _, _ ->
                dwManager.disableScanning()
                isEnabled = false
                onBackPressedDispatcher.onBackPressed()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
})
```

---

### BLK-09 — Edge-to-edge not implemented in three activities
**API level**: 35 (visual regression — content drawn behind status bar and navigation bar)
**Files**:
- `MainActivity.kt:35–37` — comment confirms missing inset handling
- `AddItemActivity.kt:41–42` — comment confirms missing inset handling
- `ExportActivity.kt:31` — comment confirms missing inset handling

**VERIFY result**: Confirmed absent. `SettingsActivity` is correctly implemented (uses `WindowCompat.setDecorFitsSystemWindows(window, false)` + `ViewCompat.setOnApplyWindowInsetsListener` — this is the reference implementation for the other three activities).

**Fix**: Apply the same pattern as `SettingsActivity` to `MainActivity`, `AddItemActivity`, and `ExportActivity`. In each `onCreate`, after `setContentView`:
```kotlin
WindowCompat.setDecorFitsSystemWindows(window, false)
val content = findViewById<View>(android.R.id.content)
ViewCompat.setOnApplyWindowInsetsListener(content) { view, insets ->
    val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
    view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
    insets
}
```

---

## 2. REQUIRED CHANGES

These do not crash the app but cause silent failure, permission denial, or broken behavior.

---

### REQD-01 — `POST_NOTIFICATIONS` missing from manifest and no runtime request
**API level**: 33 (silent drop — notifications never shown)
**Files**:
- `AndroidManifest.xml:11` — comment confirms permission is absent
- `util/NotificationHelper.kt:70, 91` — `notify()` called with no permission check

**VERIFY result**: Confirmed absent — no `POST_NOTIFICATIONS` in manifest, and no `requestPermissions` or `registerForActivityResult(RequestPermission)` call anywhere in the codebase for this permission.

**Fix**:
1. Add to manifest: `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />`
2. Request at runtime before the first notification (suggest in `MainActivity.onResume` or on first use):
```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    val launcher = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (!granted) { /* update UI: disable notification preference */ }
    }
    launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
}
```

---

### REQD-02 — Legacy storage permissions; `READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE`
**API level**: 33 (permission denied for media reads; `WRITE_EXTERNAL_STORAGE` silently no-op since API 29)
**Files**:
- `AndroidManifest.xml:5, 7` — both legacy permissions declared without `maxSdkVersion`
- `ExportActivity.kt:56–65` — requests `WRITE_EXTERNAL_STORAGE` at runtime and blocks export if denied

**VERIFY result**: Confirmed. `WRITE_EXTERNAL_STORAGE` has been meaningless since the app targeted API 29+; the `onRequestPermissionsResult` block in `ExportActivity` will never return `PERMISSION_GRANTED` on any device running API 30+, so exports are silently blocked unless the storage migration (REQD-06) is done first.

**Fix**:
1. Replace in manifest:
```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
<!-- WRITE_EXTERNAL_STORAGE: remove entirely or scope to maxSdkVersion="28" -->
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"
    android:minSdkVersion="33" />
```
2. See also REQD-06 — the storage migration fix resolves the `WRITE_EXTERNAL_STORAGE` dependency entirely.

---

### REQD-03 — `registerReceiver()` missing export flag (DataWedge scan receiver)
**API level**: 33 (exception thrown at `registerReceiver` on API 33+ targets; DataWedge scans never arrive)
**File**: `MainActivity.kt:117`

**FOUND in log (Zebra-specific section)**: Yes, flagged in both the API 33 section and the Zebra-specific section.

**VERIFY result**: Confirmed — `registerReceiver(scanReceiver, filter)` is called with no flag. The comment in the code acknowledges the issue.

**Details**: The DataWedge `ScanReceiver` is registered dynamically in `setupScanReceiver()`. DataWedge broadcasts are sent from a separate system process but are targeted at this specific app (explicit broadcast). The correct flag is `RECEIVER_NOT_EXPORTED` — the receiver should not be reachable from third-party apps, only from DataWedge. On API 34+, omitting the flag throws an exception immediately.

**Fix**:
```kotlin
ContextCompat.registerReceiver(
    this,
    scanReceiver,
    filter,
    ContextCompat.RECEIVER_NOT_EXPORTED
)
```
Using `ContextCompat.registerReceiver` handles the version check automatically (no-op on older APIs).

---

### REQD-04 — Custom `SplashActivity` — double-splash on API 31+
**API level**: 31 (UX regression — system splash plays first, then app's 2-second animated splash)
**File**: `SplashActivity.kt`

**FOUND in log**: Yes.

**Fix**: Migrate to `androidx.core:core-splashscreen`. Remove `SplashActivity` and its layout. Move DataWedge profile creation to `MainActivity.onCreate`. Add the splash screen library and configure the theme:
```gradle
implementation 'androidx.core:core-splashscreen:1.0.1'
```
```xml
<!-- themes.xml -->
<style name="Theme.InventoryApp.Starting" parent="Theme.SplashScreen">
    <item name="windowSplashScreenBackground">@color/brand_color</item>
    <item name="windowSplashScreenAnimatedIcon">@drawable/ic_launcher</item>
    <item name="postSplashScreenTheme">@style/Theme.InventoryApp</item>
</style>
```
Make the launcher intent-filter point to `MainActivity`. In `MainActivity.onCreate` before `setContentView`: `installSplashScreen()`.

---

### REQD-05 — `startActivityForResult` / `onActivityResult` / `onRequestPermissionsResult` deprecated
**API level**: 33+ (deprecated; enforced style on API 35; predictive back interacts with these)
**Files**:
- `MainActivity.kt:57, 65, 75, 136` — three `startActivityForResult` calls, one `onActivityResult`
- `AddItemActivity.kt:83, 145` — two `startActivityForResult` calls, `onRequestPermissionsResult`, `onActivityResult`
- `ExportActivity.kt:56–65, 71–84` — `onRequestPermissionsResult` for storage permission

**FOUND in log**: Yes, all flagged.

**Fix**: Replace with `registerForActivityResult` and `ActivityResultContracts`. For `MainActivity`:
```kotlin
private val editItemLauncher = registerForActivityResult(
    ActivityResultContracts.StartActivityForResult()
) { result ->
    if (result.resultCode == RESULT_OK) {
        val item = result.data?.getParcelableExtra("new_item", InventoryItem::class.java)
            ?: return@registerForActivityResult
        // handle item
    }
}
```
For camera in `AddItemActivity`: use `ActivityResultContracts.TakePicture()`.
For gallery: use `ActivityResultContracts.PickVisualMedia()` (Photo Picker).
For permissions: use `ActivityResultContracts.RequestPermission()`.

Also fix `MainActivity.getParcelableExtraCompat` — the inline helper uses the untyped `@Suppress("DEPRECATION")` form. On API 33+, use `intent.getParcelableExtra("new_item", InventoryItem::class.java)`.

---

### REQD-06 — Storage: `Environment.getExternalStorageDirectory()` and hardcoded `/sdcard/` paths
**API level**: 29+ (writes silently fail; paths inaccessible under scoped storage)
**Files**:
- `util/StorageHelper.kt:22` — `getExportDirectory()` uses `Environment.getExternalStorageDirectory()`
- `util/StorageHelper.kt:36` — `getPhotosDirectory()` uses hardcoded `/sdcard/InventoryApp/photos`
- `util/StorageHelper.kt:50` — `getTempDirectory()` uses `Environment.getExternalStorageDirectory()`
- `ExportActivity.kt:110` — inline `Environment.getExternalStorageDirectory()` in `writeExportFile()`
- `AddItemActivity.kt:137` — delegates to `StorageHelper.getPhotoFile()` which uses the hardcoded path

**FOUND in log**: Yes, all flagged.

**Fix per path**:

| Path | New API |
|------|---------|
| `getExportDirectory` | `context.getExternalFilesDir("exports")` for private export, or `MediaStore.Downloads` if it must appear in the user's Downloads folder |
| `getPhotosDirectory` | `context.getExternalFilesDir(Environment.DIRECTORY_PICTURES)` |
| `getTempDirectory` | `context.cacheDir` or `context.externalCacheDir` |
| `ExportActivity.writeExportFile` | Same as `getExportDirectory` above |

After this change, remove the `WRITE_EXTERNAL_STORAGE` permission check in `ExportActivity.exportInventory()` — no permission is needed to write to `getExternalFilesDir()`.

---

### REQD-07 — `SCHEDULE_EXACT_ALARM` not re-checked in `onResume` (silent revocation on update)
**API level**: 34 (permission silently revoked on app update — alarms never fire after OTA/update)
**File**: No `onResume` override exists in any activity that re-checks the exact alarm permission.

**VERIFY result (canScheduleExactAlarms in onResume)**: Confirmed absent. The scan log flagged the missing guard at schedule-time (BLK-05 above). This is a separate, additional requirement: `SCHEDULE_EXACT_ALARM` is also silently revoked on app update starting API 34. There is no `onResume` check anywhere.

**Fix**: Add to `SettingsActivity.onResume` (since that is where alarm scheduling is triggered) and to `MainActivity.onResume`:
```kotlin
override fun onResume() {
    super.onResume()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val alarmManager = getSystemService(AlarmManager::class.java)
        if (!alarmManager.canScheduleExactAlarms()) {
            // Revoked after update — prompt user to re-grant
            startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM))
        }
    }
}
```

---

### REQD-08 — Build configuration outdated
**File**: `app/build.gradle`

Items (all mechanical — `scan.sh --fix` applies these automatically):
- `compileSdkVersion 30` → `compileSdk 35` (integer form required for AGP 8)
- `targetSdkVersion 30` → `targetSdk 35`
- `sourceCompatibility/targetCompatibility JavaVersion.VERSION_1_8` → `VERSION_17`
- `kotlinOptions.jvmTarget '1.8'` → `'17'`
- Gradle wrapper pre-8.x → upgrade to 8.x+ for AGP 8 / `targetSdk 35`

Additional dependency updates required (not detected by scanner — outdated versions incompatible with AGP 8 + API 35 builds):
- `androidx.core:core-ktx:1.6.0` → 1.13.1+
- `androidx.appcompat:appcompat:1.3.1` → 1.7.0+
- `com.google.android.material:material:1.4.0` → 1.12.0+
- `androidx.recyclerview:recyclerview:1.2.0` → 1.3.2+
- Add: `androidx.activity:activity-ktx:1.9.3` (required for `registerForActivityResult`, `OnBackPressedCallback`)
- Add: `androidx.core:core-splashscreen:1.0.1` (for REQD-04)
- Add: `androidx.work:work-runtime-ktx:2.9.1` (for BLK-06 coroutines/WorkManager migration)

---

## 3. ZEBRA-SPECIFIC ISSUES

---

### ZEB-01 — DataWedge `ScanReceiver` (manifest): exported flag must be `true`
**File**: `AndroidManifest.xml:52–57`

The manifest-registered `ScanReceiver` must be `android:exported="true"` because DataWedge runs in a separate system process and delivers scan broadcasts from outside this app's process. Without `exported="true"`, DataWedge broadcasts are silently dropped on API 31+. This is a special case that differs from the other receivers in BLK-01 (which should all be `false`).

The dynamically registered `ScanReceiver` in `MainActivity.setupScanReceiver()` uses the same intent filter (`com.example.inventoryapp.SCAN_RESULT`) as both the manifest receiver and the DataWedge profile intent output. Having both registrations is redundant — choose one:
- **Recommended**: keep only the dynamic registration (lifecycle-bound, unregistered in `onDestroy`). Remove the manifest `<receiver>` for `ScanReceiver`. Use `RECEIVER_NOT_EXPORTED` on the dynamic registration (REQD-03) — DataWedge's explicit broadcast reaches `RECEIVER_NOT_EXPORTED` receivers because it targets the app's package directly.
- **Alternative**: keep only the manifest receiver if scan results must arrive when the activity is not in the foreground.

---

### ZEB-02 — DataWedge profile: intent delivery mode "2" (broadcast) is correct
**File**: `datawedge/DataWedgeManager.kt:68`

`intent_delivery = "2"` configures DataWedge to deliver scan results as broadcasts. This is the correct mode for a `BroadcastReceiver`-based integration and requires no change. Note: DataWedge broadcasts to this app are explicit (targeted at the app's package), so they are not affected by Android's implicit broadcast restrictions. Confirm the DataWedge profile output action (`com.example.inventoryapp.SCAN_RESULT`) matches the filter registered in `setupScanReceiver()` — they match in the current code.

---

### ZEB-03 — DataWedge profile created in `SplashActivity` — must move when splash is removed
**File**: `SplashActivity.kt:34–35`

`DataWedgeManager.createInventoryProfile()` is called during the splash delay. When `SplashActivity` is removed as part of REQD-04, this call must move to `MainActivity.onCreate`. Profile creation via `SET_CONFIG` is idempotent — calling it on each launch ensures the profile remains configured after a factory reset or after DataWedge is reinstalled.

---

### ZEB-04 — No EMDK usage detected
The scanner is accessed entirely through DataWedge, which is the correct pattern for this app type. No EMDK lifecycle issues to address. The scan log confirmed this with `[OK] EMDK usage`. If direct scanner control is ever required, add EMDK and ensure `EMDKManager.release()` is called in both `onPause` and `onDestroy`.

---

### ZEB-05 — Storage paths on Zebra devices
`/sdcard/` paths in `StorageHelper.kt` are non-functional under scoped storage. On Zebra devices, the external storage path may differ by model (TC, MC, ET series) — hardcoded paths are additionally unreliable in an enterprise fleet context. The `getExternalFilesDir()` fix in REQD-06 is device-agnostic and resolves this entirely.

---

## 4. SUGGESTED PHASE ORDER

Based on the issues found, apply the migration phases in this order:

| Step | Phase | What it addresses |
|------|-------|-------------------|
| 1 | **Phase 1 — Assessment** | Run `./gradlew lint` to baseline all warnings before making changes. Confirms the issues found here and surfaces any additional library-level deprecations. |
| 2 | **Phase 0 mechanical fixes** | Apply `scan.sh --fix`: update `targetSdk`, `compileSdk`, Java compat, Gradle wrapper, `Handler()` no-arg (BLK-07 partial). |
| 3 | **Phase 2a — targetSdk 30→31** | Fix BLK-01 (`android:exported`), BLK-02 (`PendingIntent` flags), BLK-03 (notification trampoline), BLK-04 (BouncyCastle), BLK-05 (exact alarm + manifest permission), REQD-04 (SplashScreen library). Bump `targetSdk` to 31 and verify on API 31 device before continuing. |
| 4 | **Phase 3 — Storage Migration** | Fix REQD-06 (all storage paths and `Environment.getExternalStorageDirectory()` calls). Do this before bumping to API 33 so scoped storage is correct and the `WRITE_EXTERNAL_STORAGE` dependency in `ExportActivity` is resolved. |
| 5 | **Phase 2b — targetSdk 31→33** | Fix BLK-06 (`AsyncTask` → coroutines), REQD-01 (`POST_NOTIFICATIONS`), REQD-02 (legacy permissions), REQD-03 (`registerReceiver` flag), REQD-05 (`ActivityResultContracts`). Bump `targetSdk` to 33. |
| 6 | **Phase 2c — targetSdk 33→34** | Fix REQD-07 (`canScheduleExactAlarms` in `onResume`). Verify implicit intent behavior (no implicit internal intents detected, but confirm after refactor). Bump `targetSdk` to 34. |
| 7 | **Phase 2d — targetSdk 34→35** | Fix BLK-08 (`OnBackPressedCallback`), BLK-09 (edge-to-edge in three activities), REQD-08 remaining build config and dependency versions. Bump `targetSdk` to 35. |
| 8 | **Phase 4 — Jetpack Libraries** | Update all dependency versions (core-ktx, appcompat, material, recyclerview, activity-ktx). Resolves any remaining compatibility warnings after target bump. |

---

## 5. TESTING CHECKLIST

### Part A — Per-Issue Tests

| ID | What to test | API level / device | Pass criteria |
|----|-------------|-------------------|---------------|
| BLK-01 | Install APK via ADB or MDM push | API 31+ (TC52 or emulator) | APK installs without `INSTALL_FAILED_MISSING_XML_ATTRIBUTE`; no install error |
| BLK-02 | Tap low-stock notification; observe alarm scheduling | API 31+ | No `IllegalArgumentException` in logcat; notification tap opens `MainActivity` |
| BLK-03 | Trigger a low-stock alert; tap the notification | API 31+ | `MainActivity` opens directly with no delay or silent failure; `LowStockAlertReceiver` is gone |
| BLK-04 | Export inventory with encryption enabled | API 31+ (TC52) | Export completes; no `NoSuchProviderException` in logcat |
| BLK-05 | Save settings with notifications enabled (first time) | API 31+ | Alarm schedules without `SecurityException`; verify via `adb shell dumpsys alarm` |
| BLK-05 | Revoke `SCHEDULE_EXACT_ALARM` in device settings; tap Save | API 31+ | App navigates to system Settings alarm permission screen; does not crash |
| REQD-07 | Update the app via ADB install; open the app | API 34+ | `canScheduleExactAlarms()` is re-checked in `onResume`; system Settings prompt shown if revoked |
| BLK-06 | Load inventory list; add, update, and delete items | API 33+ | All operations complete without `NoClassDefFoundError` for `AsyncTask` |
| BLK-07 | Launch app | API 33+ | Splash appears; no `RuntimeException` from `Handler()` no-arg constructor |
| BLK-08 | Press back (button and swipe) from `MainActivity` | API 35 physical device | Exit confirmation dialog appears; completing swipe before release shows preview |
| BLK-09 | Open `MainActivity`, `AddItemActivity`, `ExportActivity`; rotate device | API 35 | Content not clipped by status bar or navigation bar in both portrait and landscape |
| BLK-09 | Switch between gesture and 3-button navigation | API 35 | Layout adjusts correctly in both navigation modes; no content hidden behind nav bar |
| REQD-01 | Fresh install; open app for first time | API 33+ | `POST_NOTIFICATIONS` dialog appears; notifications appear after grant |
| REQD-01 | Deny `POST_NOTIFICATIONS`; trigger low-stock condition | API 33+ | No crash; no silent exception; notification-related UI gracefully disabled or shows rationale |
| REQD-02 | Open gallery picker in `AddItemActivity` | API 33+ | `READ_MEDIA_IMAGES` is requested (not `READ_EXTERNAL_STORAGE`); picker opens |
| REQD-03 | Scan a barcode in `MainActivity` | API 33+ (TC52 with DataWedge) | Scan result arrives; item found or add-item flow opens; no `SecurityException` at `registerReceiver` |
| REQD-04 | Cold launch on API 31+ | API 31+ | Single splash screen shown (system splash only); no second custom 2-second animated splash |
| REQD-05 | Add new item; edit existing item; pick photo from gallery | All | Correct results returned; no `ActivityNotFoundException`; item saved correctly |
| REQD-06 | Export CSV | API 29+ | File written to `getExternalFilesDir("exports")`; path shown in UI is accessible; no storage permission dialog |
| REQD-06 | Take photo for item | API 29+ | Photo saved to `getExternalFilesDir(DIRECTORY_PICTURES)`; displayed correctly in `AddItemActivity` |
| ZEB-01 | Scan barcode after fresh DataWedge profile creation | TC52 (API 33+) | Scan result arrives in `MainActivity`; barcode lookup completes; no silent drop |
| ZEB-03 | Factory-reset device; install app; launch | TC52 | DataWedge profile "InventoryApp" is created on first launch from `MainActivity.onCreate`; scanning works immediately |

---

### Part B — Behavioral Changes With No Code Fix Required

These changes take effect automatically after the `targetSdk` bump but require no code change. Verify each on device and inform QA testers.

**Overscroll stretch effect (API 31)**
From API 31, overscroll produces a stretch animation instead of a blue glow. The inventory `RecyclerView` will stretch at the top and bottom when scrolled past its content. No code change is needed, but test visually — any custom `EdgeEffect` overrides or theme attributes that styled the glow effect should be removed. Verify on a device with a light background where the stretch is visible.

**Camera and microphone privacy indicator (API 31)**
Android 12+ shows a green dot in the status bar corner when the camera or microphone is in active use. When `AddItemActivity` launches the camera intent, the privacy dot will appear and disappear when the intent returns. This is expected system behavior; inform QA testers so it is not filed as a defect.

**Clipboard access toast (API 33)**
When any part of the app reads clipboard content, Android 13+ automatically shows a system toast at the bottom of the screen. If any screen shows a custom "Copied!" or "Pasted!" toast, it will now appear alongside the system toast. Review any clipboard-related feedback in `EditText` fields (e.g., barcode or location fields in `AddItemActivity`) to check for duplicate toasts.

**`POST_NOTIFICATIONS` "Only this time" grant (API 33)**
The `POST_NOTIFICATIONS` runtime dialog includes an "Only this time" option. The permission expires when the app is backgrounded. Test the notification flow when this option is selected — verify the app handles a subsequent denied permission check gracefully on the next notification attempt without crashing or producing unhandled exceptions.

**Notification UI — 1-tap expansion (API 33)**
Single-line notifications from API 33+ require only one tap to expand (previously two). The low-stock notification `setContentText` with a multi-item summary will display differently. Verify the notification content and the action button (if any) are readable and tappable in the notification shade.

**Partial photo access — "Select photos" grant (API 34)**
When `READ_MEDIA_IMAGES` is requested on API 34+, the user sees an option to grant access only to selected photos. `AddItemActivity` must handle the case where `READ_MEDIA_VISUAL_USER_SELECTED` is granted but `READ_MEDIA_IMAGES` is not. The system Photo Picker (`ActivityResultContracts.PickVisualMedia`) does not require any media permission and avoids this complexity entirely — consider switching the gallery button to `PickVisualMedia` as part of the REQD-05 refactor.

**Predictive back gesture preview (API 35)**
With predictive back enforced on API 35, a swipe-right from the left edge of `MainActivity` shows a preview of the app icon (indicating the app will exit) before the user releases. Once BLK-08 is fixed, QA should verify:
1. The preview appears during the swipe gesture (before release).
2. Completing the swipe triggers the exit confirmation dialog (the `OnBackPressedCallback`).
3. Canceling the dialog returns the user to `MainActivity`.
Test with gesture navigation enabled (Settings → Navigation → Gesture Navigation).

**`elegantTextHeight` default `true` (API 35)**
All `TextView` instances will use taller, more readable line metrics by default on API 35. Test every screen for text clipping, especially:
- Inventory list rows in `InventoryAdapter` — fixed-height rows with barcode, name, quantity, and location labels
- Export status text in `ExportActivity` — may show a long file path
- Settings form labels in `SettingsActivity`

On Zebra WS50/WS501 (square, compact display), fixed-row heights are particularly prone to clipping at the new line height. Any rows or labels sized to compact font metrics should be validated.

**Notification cooldown (API 35)**
If the app posts many low-stock notifications in quick succession (e.g., a large import triggers `checkLowStock` repeatedly), Android 15 may temporarily reduce notification priority. The current `showLowStockNotification` uses a fixed `NOTIFICATION_ID_LOW_STOCK = 1001`, so calling `notify()` again with the same ID updates the existing notification rather than stacking new ones. Verify this behavior on API 35 — no burst of separate notifications should appear for a multi-item low-stock check.

**Background activity launch (API 35)**
`StockCheckReceiver.onReceive()` calls `InventoryRepository.checkLowStock()` which posts a notification. After BLK-03 is fixed, it no longer attempts to launch an activity directly. Verify that tapping the notification from a locked screen or background state still correctly opens `MainActivity` via the direct `PendingIntent`.

**TLS endpoint verification**
The app declares `INTERNET` permission. On API 35, connections to TLS 1.0/1.1 endpoints fail silently. Verify that any backend API or update endpoint this app contacts supports TLS 1.2+. Coordinate with the infrastructure team. No code change in the app is required if the endpoints are already on TLS 1.2+. Validate using a network proxy (Charles, Wireshark) on an API 35 emulator — confirm all connections complete successfully.

---

*End of Phase 0 migration plan.*
