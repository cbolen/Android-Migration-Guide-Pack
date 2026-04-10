# InventoryApp Migration Plan — targetSdk 30 → 35

**Generated**: 2026-04-09  
**Scanner log**: migrate.log (12 [FOUND], 10 [VERIFY])  
**Source reviewed**: AndroidManifest.xml, all 16 Kotlin files, app/build.gradle  
**Starting SDK**: compileSdk 30 / targetSdk 30 / minSdk 26  
**Target SDK**: compileSdk 35 / targetSdk 35

Every `[FOUND]` and `[VERIFY]` item from migrate.log appears below, with additional
issues discovered by cross-file analysis that the scanner did not detect.

---

## 1. BLOCKING ISSUES

Issues that cause install failure, a runtime crash, or a hard-blocked feature.

---

### B-01 — `android:exported` missing on five manifest components
**API level**: 31 | **Impact**: APK fails to install on API 31+ devices  
**Source**: migrate.log [VERIFY] (confirmed genuine — all five components are missing the attribute)

| Component | File | Line | Required value |
|-----------|------|------|----------------|
| `.MainActivity` | AndroidManifest.xml | 32 | `android:exported="false"` (internal action, not for third parties) |
| `.AddItemActivity` | AndroidManifest.xml | 40 | `android:exported="false"` (same) |
| `.datawedge.ScanReceiver` | AndroidManifest.xml | 52 | See B-09 — remove from manifest entirely |
| `.LowStockAlertReceiver` | AndroidManifest.xml | 61 | `android:exported="false"` (only receives intents from this app) |
| `.util.StockCheckReceiver` | AndroidManifest.xml | 68 | `android:exported="false"` (only receives alarms scheduled by this app) |

**Fix**: Add `android:exported` to each component. The correct value for internal actions is `false`. ScanReceiver should be removed from the manifest entirely (see B-09).

---

### B-02 — `PendingIntent` created without `FLAG_IMMUTABLE`
**API level**: 31 | **Impact**: `IllegalArgumentException` at runtime whenever a `PendingIntent` is created  
**Source**: migrate.log [VERIFY] (confirmed — all four callsites pass `flags = 0`)

| File | Line | Call |
|------|------|------|
| NotificationHelper.kt | 57 | `PendingIntent.getBroadcast(context, 0, trampolineIntent, 0)` |
| NotificationHelper.kt | 78 | `PendingIntent.getActivity(context, 1, mainIntent, 0)` |
| StockAlarmScheduler.kt | 39 | `PendingIntent.getBroadcast(context, REQUEST_CODE, intent, 0)` |
| StockAlarmScheduler.kt | 64 | `PendingIntent.getBroadcast(context, REQUEST_CODE, intent, 0)` |

**Fix**: Replace `0` with `PendingIntent.FLAG_IMMUTABLE` on every call. These intents do not need to be mutable, so `FLAG_IMMUTABLE` is correct for all four.

```kotlin
// Before
PendingIntent.getActivity(context, 1, mainIntent, 0)
// After
PendingIntent.getActivity(context, 1, mainIntent, PendingIntent.FLAG_IMMUTABLE)
```

---

### B-03 — BouncyCastle (`"BC"`) provider removed
**API level**: 31 | **Impact**: `NoSuchProviderException` at runtime whenever export encryption/decryption is called  
**Source**: migrate.log [FOUND]

| File | Lines | Call |
|------|-------|------|
| CryptoHelper.kt | 37 | `Cipher.getInstance(TRANSFORMATION, PROVIDER)` — encrypt |
| CryptoHelper.kt | 52 | `Cipher.getInstance(TRANSFORMATION, PROVIDER)` — decrypt |

**Fix**: Remove the second argument entirely. The default JCA provider (Conscrypt) supports `AES/CBC/PKCS5Padding`:

```kotlin
// Before
val cipher = Cipher.getInstance(TRANSFORMATION, PROVIDER)  // "BC" throws on A12+
// After
val cipher = Cipher.getInstance(TRANSFORMATION)
```

Also delete the `PROVIDER = "BC"` constant in the `CryptoHelper` companion object.

---

### B-04 — Notification trampoline blocked
**API level**: 31 | **Impact**: Tapping a low-stock notification does nothing — `Activity` launch from `BroadcastReceiver` is blocked  
**Source**: migrate.log [FOUND]

**Root cause**: `NotificationHelper.kt:52–57` sets the notification's content intent to a `PendingIntent` targeting `LowStockAlertReceiver`, which in turn calls `startActivity(MainActivity)`. This two-hop pattern is blocked on API 31+.

| File | Line | Issue |
|------|------|-------|
| NotificationHelper.kt | 52–57 | Trampoline `PendingIntent` targets `LowStockAlertReceiver` |
| LowStockAlertReceiver.kt | 17–22 | Entire class is the trampoline; calls `startActivity()` in `onReceive()` |

**Fix**: In `NotificationHelper.showLowStockNotification()`, replace the `BroadcastReceiver` `PendingIntent` with one targeting `MainActivity` directly. Then remove `LowStockAlertReceiver` entirely (and its manifest entry).

```kotlin
// Replace trampolineIntent / getBroadcast with:
val directIntent = Intent(context, MainActivity::class.java).apply {
    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
}
val pendingIntent = PendingIntent.getActivity(
    context, 0, directIntent, PendingIntent.FLAG_IMMUTABLE
)
```

---

### B-05 — `setExactAndAllowWhileIdle()` without `canScheduleExactAlarms()` guard
**API level**: 31 | **Impact**: `SecurityException` at runtime when alarm is scheduled or rescheduled  
**Source**: migrate.log [VERIFY] and [FOUND] (confirmed — guard is absent from both scheduling sites)

| File | Line | Issue |
|------|------|-------|
| StockAlarmScheduler.kt | 53 | `setExactAndAllowWhileIdle()` called without permission check |
| StockCheckReceiver.kt | 76 | `scheduleDailyCheck()` called from alarm callback — also unguarded |
| AndroidManifest.xml | — | `SCHEDULE_EXACT_ALARM` permission not declared |

**Fix**:

1. Add permission to manifest:
```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

2. Guard the alarm call in `StockAlarmScheduler.scheduleDailyCheck()`:
```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    val alarmManager = context.getSystemService(AlarmManager::class.java)
    if (!alarmManager.canScheduleExactAlarms()) {
        context.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        })
        return
    }
}
```

The same guard is needed in `StockCheckReceiver.onReceive()` where `scheduleDailyCheck()` is called to reschedule — if the permission is revoked between alarm firings, the reschedule attempt also throws.

---

### B-06 — `AsyncTask` removed
**API level**: 33 | **Impact**: `NoClassDefFoundError` at runtime on any database operation  
**Source**: migrate.log [FOUND]

| File | Lines | Classes |
|------|-------|---------|
| InventoryRepository.kt | 38, 46, 54, 62, 67 | `FetchAllTask`, `FindByBarcodeTask`, `InsertItemTask`, `UpdateItemTask`, `CheckLowStockTask` |

**Fix**: Replace all five inner `AsyncTask` subclasses with Kotlin coroutines.

```kotlin
// Example: getAllItems with coroutines
fun getAllItems(callback: (List<InventoryItem>) -> Unit) {
    CoroutineScope(Dispatchers.IO).launch {
        val items = database.getAllItems()
        withContext(Dispatchers.Main) { callback(items) }
    }
}
```

For proper lifecycle management, expose `suspend` functions and call from `viewModelScope` in a `ViewModel`. The current callback pattern can be preserved temporarily as a migration step.

---

### B-07 — `registerReceiver()` without export flag
**API level**: 34 | **Impact**: `IllegalArgumentException` at runtime when `MainActivity` starts  
**Source**: migrate.log [VERIFY] (confirmed — the flag is absent; the code comment acknowledges the fix but has not been applied)

| File | Line | Issue |
|------|------|-------|
| MainActivity.kt | 117 | `registerReceiver(scanReceiver, filter)` — no export flag |

**Fix**: Use `ContextCompat.registerReceiver()` with `RECEIVER_NOT_EXPORTED`. DataWedge broadcasts are directed explicitly at this app's package, so `NOT_EXPORTED` is correct:

```kotlin
ContextCompat.registerReceiver(
    this, scanReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED
)
```

---

### B-08 — `onBackPressed()` override — predictive back enforcement
**API level**: 35 | **Impact**: Back navigation broken; predictive back swipe preview does not appear  
**Source**: migrate.log [FOUND]

| File | Line | Issue |
|------|------|-------|
| MainActivity.kt | 154 | `override fun onBackPressed()` |

**Fix**: Replace with `OnBackPressedCallback`. The exit dialog logic is preserved:

```kotlin
onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
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

### B-09 — `ScanReceiver` static manifest registration has no no-arg constructor *(not detected by scanner)*
**API level**: 31 | **Impact**: `RuntimeException` (InstantiationException) when DataWedge delivers to the statically-registered receiver after `android:exported="true"` is added (fix B-01)  
**Cross-file interaction**: AndroidManifest.xml:52–57 + ScanReceiver.kt

`ScanReceiver` requires a lambda callback in its constructor (`onScanResult: (String, String) -> Unit`). Android instantiates manifest-registered receivers using a no-arg constructor. Fixing B-01 by adding `android:exported="true"` to the manifest registration means DataWedge will be able to deliver to it — and will crash when it tries to construct the class.

Additionally, `ScanReceiver` is also registered dynamically in `MainActivity.setupScanReceiver()` for the same action (`com.example.inventoryapp.SCAN_RESULT`). Both registrations would match the same DataWedge broadcast, resulting in double delivery.

**Fix**: Remove `ScanReceiver` from `AndroidManifest.xml` entirely (lines 52–57). Rely exclusively on the dynamic registration in `MainActivity`. The `RESULT_ACTION` listener for DataWedge API responses should also be handled in the dynamic receiver.

---

## 2. REQUIRED CHANGES

Silent failures, permission denials, or deprecated APIs enforced in the target SDK range.

---

### R-01 — `POST_NOTIFICATIONS` not declared; no runtime request
**API level**: 33 | **Impact**: All notifications silently dropped; low-stock alerts never shown  
**Source**: migrate.log [VERIFY] (confirmed — permission absent from manifest, no runtime request anywhere)

| File | Line | Issue |
|------|------|-------|
| AndroidManifest.xml | 11 | Permission commented out / missing |
| NotificationHelper.kt | 71 | `manager.notify()` — no permission check before this call |
| NotificationHelper.kt | 91 | Same for export-complete notification |

**Fix**:

1. Add to manifest:
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

2. Request at runtime before any notification fires (e.g., when the user enables notifications in `SettingsActivity`):
```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    requestPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
}
```

---

### R-02 — Storage permissions outdated; export always fails
**API level**: 30/33 | **Impact**: CSV export always blocked by permission denial; photo capture silently fails  
**Source**: migrate.log [FOUND] + [VERIFY]

**Permission issues** (AndroidManifest.xml:4–7):

| Permission | Issue | Fix |
|-----------|-------|-----|
| `READ_EXTERNAL_STORAGE` | Denied on API 33+ targets; no `maxSdkVersion` guard | Add `android:maxSdkVersion="32"`; add `READ_MEDIA_IMAGES` for API 33+ |
| `WRITE_EXTERNAL_STORAGE` | Ignored on API 30+ for apps targeting API 29+; still checked in code | Remove the permission check from `ExportActivity`; switch to `getExternalFilesDir()` |

**Code issues**:

| File | Line | Issue | Fix |
|------|------|-------|-----|
| ExportActivity.kt | 56–65 | Checks `WRITE_EXTERNAL_STORAGE` which is always denied on API 30+ targets; export never runs | Remove permission check; switch storage path |
| ExportActivity.kt | 110 | `Environment.getExternalStorageDirectory()` — not writable | Replace with `getExternalFilesDir("exports")` |
| StorageHelper.kt | 22 | `Environment.getExternalStorageDirectory()` for exports | Replace with `context.getExternalFilesDir("exports")` |
| StorageHelper.kt | 36 | `File("/sdcard/InventoryApp/photos")` hardcoded path | Replace with `context.getExternalFilesDir(Environment.DIRECTORY_PICTURES)` |
| StorageHelper.kt | 50 | `Environment.getExternalStorageDirectory()` for temp | Replace with `context.cacheDir` or `context.getExternalFilesDir("temp")` |

`getExternalFilesDir()` requires no permission and files are deleted on uninstall. If exported CSVs must be visible in the system Files app after uninstall, use `MediaStore.Downloads` instead.

---

### R-03 — `canScheduleExactAlarms()` not re-checked in `onResume`
**API level**: 34 | **Impact**: Daily low-stock alarm silently stops firing after an app update  
**Source**: migrate.log [VERIFY] (confirmed absent — neither `MainActivity` nor `SettingsActivity` has this check in `onResume`)

On Android 14, `SCHEDULE_EXACT_ALARM` is silently revoked when the app is updated. No broadcast is sent; the permission simply disappears.

**Fix**: Add to `MainActivity.onResume()`:

```kotlin
override fun onResume() {
    super.onResume()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val alarmManager = getSystemService(AlarmManager::class.java)
        if (!alarmManager.canScheduleExactAlarms()) {
            startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM))
        }
    }
    dwManager.switchToProfile("InventoryApp")
}
```

---

### R-04 — Edge-to-edge inset handling missing on three activities
**API level**: 35 | **Impact**: Content drawn behind status bar and navigation bar; buttons/inputs clipped  
**Source**: migrate.log [VERIFY] (confirmed — `SettingsActivity` is correct; the other three are not)

| File | Line | Status |
|------|------|--------|
| MainActivity.kt | 35–38 | Missing — comment documents the issue |
| AddItemActivity.kt | 41–43 | Missing — comment documents the issue |
| ExportActivity.kt | 31–32 | Missing — comment documents the issue |
| SettingsActivity.kt | 28–30, 96–104 | **Correctly implemented** — reference implementation |

**Fix**: Apply the same pattern from `SettingsActivity` to the other three:

```kotlin
// In Activity.onCreate
WindowCompat.setDecorFitsSystemWindows(window, false)

// After setContentView, on the root view
ViewCompat.setOnApplyWindowInsetsListener(findViewById(android.R.id.content)) { view, insets ->
    val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
    view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
    insets
}
```

---

### R-05 — `startActivityForResult` / `onActivityResult` / `onRequestPermissionsResult` deprecated
**API level**: 33/35 | **Impact**: Deprecated APIs that must be replaced for targetSdk 35; currently produce lint warnings  
**Source**: migrate.log [FOUND]

| File | Lines | Pattern |
|------|-------|---------|
| MainActivity.kt | 57, 65, 75–93, 136 | `startActivityForResult`, `onActivityResult` |
| AddItemActivity.kt | 67–83, 93–115, 143–145 | `startActivityForResult`, `onActivityResult`, `onRequestPermissionsResult` |
| ExportActivity.kt | 52–85 | `onRequestPermissionsResult` (for the now-unnecessary `WRITE` permission) |

**Fix**: Replace with `registerForActivityResult()` contracts:

```kotlin
// Launch AddItemActivity and receive a result
private val addItemLauncher = registerForActivityResult(
    ActivityResultContracts.StartActivityForResult()
) { result ->
    if (result.resultCode == RESULT_OK) {
        val item = result.data?.let {
            IntentCompat.getParcelableExtra(it, "new_item", InventoryItem::class.java)
        }
        // handle item
    }
}

// Request camera permission
private val requestCameraPermission = registerForActivityResult(
    ActivityResultContracts.RequestPermission()
) { granted ->
    if (granted) launchCamera()
    else Toast.makeText(this, "Camera permission denied", Toast.LENGTH_SHORT).show()
}

// Pick gallery image (Photo Picker)
private val pickMedia = registerForActivityResult(
    ActivityResultContracts.PickVisualMedia()
) { uri -> uri?.let { ivPhoto.setImageURI(it); photoPath = it.toString() } }
```

`ExportActivity.onRequestPermissionsResult()` should be deleted entirely once R-02 is applied — no storage permission check is needed with `getExternalFilesDir()`.

---

### R-06 — `getParcelableExtra()` untyped — missed by scanner *(not detected by scanner)*
**API level**: 33 | **Impact**: Deprecated untyped call; produces lint error targeting API 33+  
**File**: MainActivity.kt:200–203

The scanner reported `getParcelableExtra()` as `[OK]` because the literal call is hidden inside a private extension function:

```kotlin
private inline fun <reified T : Parcelable> Intent.getParcelableExtraCompat(key: String): T? {
    @Suppress("DEPRECATION")
    return getParcelableExtra(key)  // ← untyped, deprecated API 33
}
```

**Fix**: Use `IntentCompat.getParcelableExtra()` from `androidx.core:core-ktx`, or use the typed API conditionally:

```kotlin
private inline fun <reified T : Parcelable> Intent.getParcelableExtraCompat(key: String): T? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
        getParcelableExtra(key, T::class.java)
    else
        @Suppress("DEPRECATION") getParcelableExtra(key)
}
```

---

### R-07 — `Handler()` no-arg constructor deprecated
**API level**: 30+ (lint error) | **Impact**: Lint failure; potential `NullPointerException` if no `Looper` is attached  
**Source**: migrate.log [FOUND]

| File | Line | Issue |
|------|------|-------|
| SplashActivity.kt | 42 | `Handler().postDelayed(...)` |

**Fix**: Replace with `Handler(Looper.getMainLooper())`. However, see also R-08 — the entire custom `SplashActivity` should be replaced.

---

### R-08 — Custom `SplashActivity` conflicts with system splash screen *(not detected by scanner)*
**API level**: 31 | **Impact**: Double-splash on API 31+ — system splash runs first, then the custom 2-second delay fires; combined cold-launch delay is roughly 3 seconds  
**File**: SplashActivity.kt

On API 31+, Android enforces a system-managed splash screen. The custom `SplashActivity` does not replace it — both execute. The result is: system splash → SplashActivity (2-second artificial delay) → MainActivity.

**Fix**: Replace the custom `SplashActivity` with the AndroidX `core-splashscreen` library:

```gradle
implementation 'androidx.core:core-splashscreen:1.0.1'
```

Move `DataWedgeManager.createInventoryProfile()` to `MainActivity.onCreate()` or `Application.onCreate()` to preserve initialization that currently happens during the splash delay (see also Z-03).

---

### R-09 — Build configuration: compileSdk / targetSdk / Java compatibility / Gradle wrapper
**Source**: migrate.log [FOUND]

| File | Line | Issue | Fix |
|------|------|-------|-----|
| app/build.gradle | 7 | `compileSdkVersion 30` | `compileSdk 35` |
| app/build.gradle | 11 | `targetSdkVersion 30` | `targetSdk 35` |
| app/build.gradle | 18–19 | `JavaVersion.VERSION_1_8` | `JavaVersion.VERSION_17` |
| app/build.gradle | 27 | `jvmTarget = '1.8'` | `jvmTarget = '17'` |
| gradle-wrapper.properties | — | Pre-8.x wrapper | Upgrade to Gradle 8.x+ for AGP 8 / targetSdk 35 |

Also update stale dependencies to versions compatible with AGP 8 / compileSdk 35:

```gradle
implementation 'androidx.core:core-ktx:1.13.1'              // was 1.6.0
implementation 'androidx.appcompat:appcompat:1.7.0'          // was 1.3.1
implementation 'com.google.android.material:material:1.12.0' // was 1.4.0
```

---

## 3. ZEBRA-SPECIFIC ISSUES

---

### Z-01 — `ScanReceiver` dynamic registration missing `RECEIVER_NOT_EXPORTED`
**Confirmed issue** (same as B-07 — DataWedge context)  
**File**: MainActivity.kt:111–117

DataWedge delivers scan results via an explicit broadcast targeted at this app's package. `RECEIVER_NOT_EXPORTED` is the correct flag — it prevents arbitrary third-party apps from injecting fake scan events while still allowing DataWedge (a system service) to deliver. The comment at line 114 correctly identifies the fix but it has not been applied. Fix is in B-07.

---

### Z-02 — `ScanReceiver` static manifest registration must be removed
**Confirmed issue** (same as B-09 — DataWedge context)  
**Files**: AndroidManifest.xml:52–57, ScanReceiver.kt

The manifest registers `ScanReceiver` for both `com.symbol.datawedge.api.RESULT_ACTION` and `com.example.inventoryapp.SCAN_RESULT`. `ScanReceiver` has no no-arg constructor and will crash on static delivery. It should exist only as a dynamic registration in `MainActivity`. If DataWedge API result callbacks (profile creation, etc.) are needed outside `MainActivity`, create a separate `BroadcastReceiver` with a no-arg constructor.

---

### Z-03 — DataWedge profile setup may race after `SplashActivity` is removed
**File**: SplashActivity.kt:34–35  
**Impact**: Scanner profile may not be associated before the user begins scanning in `MainActivity`

`DataWedgeManager.createInventoryProfile()` is currently called during the 2-second splash delay, giving DataWedge time to process the profile. If the custom `SplashActivity` is replaced with the system splash (R-08), this initialization window disappears.

**Fix**: Move `createInventoryProfile()` to `MainActivity.onCreate()` before `setupScanReceiver()`. Optionally register a DataWedge `RESULT_ACTION` listener to confirm the profile is ready before enabling scanning. Calling it in `Application.onCreate()` is also acceptable for earliest-possible execution.

---

### Z-04 — Stored photo paths in database will break after storage migration
**Files**: StorageHelper.kt:36, InventoryDatabase.kt, AddItemActivity.kt:139  
**Impact**: After migrating from `/sdcard/InventoryApp/photos/` to `getExternalFilesDir()`, existing `photo_path` values in the database point to the old location; photos will not display

**Fix**: When bumping `DATABASE_VERSION` in `InventoryDatabase`, add a migration step that:
1. Moves existing photo files from the old path to the new `getExternalFilesDir(DIRECTORY_PICTURES)` path
2. Updates stored `photo_path` column values in the database

**Important**: `InventoryDatabase.onUpgrade()` currently drops and recreates the table (`db.execSQL("DROP TABLE IF EXISTS...")`), which silently wipes all inventory data on any version bump. Replace this with a proper `ALTER TABLE` / data migration before incrementing `DATABASE_VERSION`.

---

### Z-05 — No EMDK usage detected
The scanner confirmed `[OK]` for EMDK lifecycle. `DataWedgeManager` uses only the DataWedge Intent API, which is the correct approach for this use case. No EMDK changes required.

---

## 4. SUGGESTED PHASE ORDER

### Phase 1 — Build baseline and lint
- Bump `compileSdk` to 35 (leave `targetSdk` at 30 initially)
- Upgrade Gradle wrapper and AGP; update dependency versions
- Run `./gradlew lint`; review `app/build/reports/lint-results-debug.html`
- Commit a clean build before making any behavioral changes

### Phase 2 — API 31 blocking fixes (targetSdk 30 → 31)
1. **B-01**: Add `android:exported` to all manifest components
2. **B-09 / Z-02**: Remove `ScanReceiver` from manifest
3. **B-04**: Fix notification trampoline — remove `LowStockAlertReceiver`; attach `MainActivity` `PendingIntent` directly to notification
4. **B-02**: Add `FLAG_IMMUTABLE` to all four `PendingIntent` calls
5. **B-03**: Remove `"BC"` provider from `CryptoHelper`
6. **B-05**: Add `SCHEDULE_EXACT_ALARM` to manifest; add `canScheduleExactAlarms()` guard in `StockAlarmScheduler` and `StockCheckReceiver`
7. **R-07**: Fix `Handler()` no-arg constructor in `SplashActivity`
- Bump `targetSdk` to 31; test on an API 31 device or emulator

### Phase 3 — Storage migration
1. **R-02**: Replace `Environment.getExternalStorageDirectory()` and `/sdcard/` paths in `StorageHelper` and `ExportActivity`
2. **Z-04**: Fix `InventoryDatabase.onUpgrade()` to use ALTER TABLE; add photo-path migration step with `DATABASE_VERSION` bump
3. Remove `WRITE_EXTERNAL_STORAGE` permission check from `ExportActivity`
4. Update manifest storage permissions with `maxSdkVersion` guards; add `READ_MEDIA_IMAGES`
- Confirm CSV export and photo capture work end-to-end on API 30+ device

### Phase 4 — API 33 fixes (targetSdk 31 → 33)
1. **B-06**: Replace all five `AsyncTask` inner classes in `InventoryRepository` with coroutines
2. **R-01**: Add `POST_NOTIFICATIONS` to manifest; add runtime permission request in `SettingsActivity` or on first launch
3. **B-07 / Z-01**: Add `RECEIVER_NOT_EXPORTED` flag to `registerReceiver()` in `MainActivity`
4. **R-06**: Fix untyped `getParcelableExtra()` wrapper in `MainActivity`
- Bump `targetSdk` to 33; test on an API 33 device

### Phase 5 — API 34 fixes (targetSdk 33 → 34)
1. **R-03**: Add `canScheduleExactAlarms()` re-check in `MainActivity.onResume()`
- Bump `targetSdk` to 34; test on an API 34 device
- Verify DataWedge scan broadcasts still arrive after the `registerReceiver` flag change

### Phase 6 — API 35 fixes (targetSdk 34 → 35)
1. **R-04**: Add edge-to-edge inset handling to `MainActivity`, `AddItemActivity`, `ExportActivity`
2. **B-08**: Replace `onBackPressed()` in `MainActivity` with `OnBackPressedCallback`
- Bump `targetSdk` to 35; test on an API 35 device
- Test both gesture navigation and 3-button navigation for edge-to-edge layout

### Phase 7 — Activity result modernization
1. **R-05**: Replace `startActivityForResult` / `onActivityResult` / `onRequestPermissionsResult` across `MainActivity`, `AddItemActivity`, `ExportActivity`
- End-to-end test: add item, edit item, camera capture, gallery pick

### Phase 8 — SplashActivity migration
1. **R-08 / Z-03**: Replace custom `SplashActivity` with AndroidX `core-splashscreen`; move DataWedge profile setup to `MainActivity.onCreate()`
- Confirm no double-splash on API 31+ devices
- Confirm DataWedge profile is active before first scan

### Phase 9 — Final cleanup
1. **R-09**: Confirm `compileSdk 35` / `targetSdk 35` / `JavaVersion.VERSION_17` are final
2. Remove remaining `@Suppress("DEPRECATION")` annotations where deprecated APIs have been replaced
3. Run final lint pass; fix any remaining warnings

---

## 5. TESTING CHECKLIST

### Part A — Per-issue verification

| ID | What to test | API level / device | Pass criteria |
|----|-------------|-------------------|---------------|
| B-01 | Install APK | API 31 device or emulator | APK installs without `INSTALL_FAILED_*` error |
| B-02 | Trigger any notification; schedule any alarm | API 31+ | No `IllegalArgumentException` in logcat |
| B-03 | Export CSV with encryption | API 31+ | Encryption/decryption completes; no `NoSuchProviderException` |
| B-04 | Receive a low-stock notification; tap it | API 31+ | `MainActivity` opens; notification tap is not silently ignored |
| B-05 | Enable daily alerts in Settings; watch logcat | API 31+ | Alarm schedules without `SecurityException`; fires at 08:00 next day |
| B-05 (manifest) | Check `SCHEDULE_EXACT_ALARM` in installed app | Any | Permission visible in Settings → App info → Permissions |
| B-06 | Add, edit, and list inventory items | API 33 | No `NoClassDefFoundError`; all DB operations complete |
| B-07 | Launch `MainActivity` | API 34 | No `IllegalArgumentException` at `registerReceiver()` |
| B-08 | Swipe back from `MainActivity` | API 35 | Predictive back animation visible on swipe; exit dialog appears on release |
| B-09 | Scan a barcode | API 31+ (after B-01 fix) | No `InstantiationException`; scan result handled exactly once |
| R-01 | Enable notifications; trigger a low-stock condition | API 33+ | Notification appears after permission granted; silent drop confirmed fixed |
| R-01 | Deny `POST_NOTIFICATIONS`; verify app behavior | API 33+ | App degrades gracefully; no crash; no silent assumption of permission |
| R-02 | Export CSV | API 30+ | File created in `getExternalFilesDir("exports")`; no `SecurityException` |
| R-02 | Take item photo | API 30+ | Photo saved in `getExternalFilesDir(DIRECTORY_PICTURES)`; displayed in `AddItemActivity` |
| R-03 | Update app on API 34 device; immediately open app | API 34 | System settings prompt for exact alarm permission appears if revoked |
| R-04 | Scroll inventory list; open add-item and export forms | API 35, gesture nav | No content hidden behind status bar or nav bar |
| R-04 | Same, 3-button navigation | API 35, 3-button nav | Same pass criteria |
| R-05 | Add new item; edit existing item; camera permission flow; gallery pick | API 33+ | Each flow completes; result returned correctly to caller |
| R-06 | Add item in `AddItemActivity`; confirm it appears in `MainActivity` | API 33+ | `InventoryItem` parcel deserialized correctly; no `ClassCastException` |
| R-07 | Cold launch | API 30+ | Splash screen appears then transitions to `MainActivity` after the delay without crashing; no `RuntimeException` from `Handler` in logcat |
| R-08 | Cold launch | API 31+ | Only one splash visible; no 2-second blank delay after system splash |
| Z-01/Z-02 | Scan a barcode | API 33+ Zebra device | Scan delivered once; no `InstantiationException`; no duplicate handling |
| Z-03 | Cold launch; immediately scan before profile setup completes | Zebra TC/MC device | Scan result arrives correctly; no missed first scan |
| Z-04 | Upgrade app on a device with stored item photos | Zebra device with live data | Photos still display after storage migration; no broken image views in list |

---

### Part B — Behavioral changes with no code fix

These are system-enforced UI and policy changes from the A11→A15 range that apply to this project and require QA verification rather than a code change.

**Camera privacy indicator (API 31+)**  
When `AddItemActivity` opens the camera for photo capture, a green dot appears in the status bar corner. No code action needed. Verify the indicator disappears immediately when the camera activity closes. Brief warehouse operators that this is a system indicator, not an error.

**Overscroll animation change (API 31+)**  
The inventory `RecyclerView` in `MainActivity` previously showed a blue glow at list edges. On API 31+, this is replaced by a stretch animation. No code change needed, but run visual QA to confirm it does not look broken.

**Root launcher activity no longer finishes on back press (API 31+)**  
`MainActivity` is the launcher activity. After implementing B-08 (`OnBackPressedCallback`), the explicit `finish()` call in the "Exit" dialog still works. However, if the user presses Cancel and the dialog is dismissed, back moves `MainActivity` to the background (rather than finishing it). Confirm `dwManager.disableScanning()` is called before `finish()` in all code paths including the dialog's positive button.

**Clipboard system toast (API 13/33)**  
If any screen copies text to the clipboard (barcodes, export file path), the system shows an automatic "Copied" toast. Remove any custom "Copied!" toasts in the app to avoid a double-toast.

**Notification permission — 'Don't ask again' path (API 33+)**  
If the user denies `POST_NOTIFICATIONS` and selects "Don't ask again", subsequent `requestPermissions` calls silently no-op. Verify that the app shows a rationale or links to system app settings in this case. The notifications toggle in `SettingsActivity` should disable itself (or show a warning) when the system permission is denied.

**Per-app language selector (API 33+)**  
After bumping targetSdk to 33, a per-app language option appears in System Settings → App info. Test that the app's date/number formatting in the exported CSV remains correct after a user-selected language change.

**Predictive back gesture preview (API 33 opt-in / API 35 enforced)**  
After B-08 is implemented, the predictive back swipe should show an animation previewing the destination. For `MainActivity`, this previews the app going to background (no next screen — the exit dialog fires on gesture release). Verify the animation is smooth in both gesture and 3-button navigation modes on API 35.

**Notification cooldown (API 35)**  
If missed alarms fire in rapid succession after a device restart, posting multiple low-stock notifications quickly may cause the system to temporarily downgrade their priority. Prefer updating a single persistent notification (same `NOTIFICATION_ID_LOW_STOCK`) with the current low-stock count rather than posting multiple notifications.

**`elegantTextHeight` defaults to `true` (API 35)**  
All `TextView`s in the app gain taller line height on API 35. Key areas to verify:

- `item_row.xml` — each inventory row may be taller than designed; check for clipping of barcode or quantity text
- `activity_add_item.xml` — form field labels and `EditText` hints may wrap or be clipped
- `activity_export.xml` — status text may overflow its container
- **Zebra WS50/WS501 (square display)** — the smaller vertical space means the line-height increase has a proportionally larger impact; run a dedicated layout pass on this form factor

**`EditText` minimum line height (API 35)**  
Single-line `EditText` fields in `AddItemActivity` (barcode, name, quantity, location, notes) may be taller than expected due to locale-aware minimum line height. Confirm fixed-height parent layouts do not clip the cursor or input text.

**Background activity launch restrictions (API 31+, tightened API 34+, API 35+)**  
After fixing the notification trampoline (B-04), confirm no other code path attempts to start an activity from a background `Service`, `BroadcastReceiver`, or `WorkManager` task without a full-screen notification intent. `StockCheckReceiver.onReceive()` fires from an alarm — it calls `checkLowStock()` which posts a notification. Verify it does not attempt to start an activity directly; the only UI surface from background context should be the notification itself.

**DataWedge scan beep not affected by audio focus restrictions (API 35)**  
DataWedge's built-in scan confirmation beep is played by the DataWedge service. It is unaffected by the API 35 audio focus restrictions. If a future feature plays a custom sound from `MainActivity` via `MediaPlayer`, that sound must be triggered while the app is in the foreground. No action required now.

**TLS 1.0/1.1 restricted (API 35)**  
The app declares `INTERNET` permission. Before bumping targetSdk to 35, verify all server endpoints support TLS 1.2 or higher. Coordinate with IT/infrastructure to check any on-premise APIs or legacy corporate servers.

**Private Space (API 35 — enterprise note)**  
For Zebra managed dedicated-use devices, MDM policy typically disables Private Space. No action required for standard enterprise deployments. If the app could be installed into Private Space, the DataWedge profile association must match the app's package name within that profile context.
