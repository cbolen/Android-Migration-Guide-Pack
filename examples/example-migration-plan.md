# Migration Plan — Zebra Inventory App (targetSdk 30 → 35)

> **Note — Contrived Example**
> This project was deliberately constructed to contain almost every possible Android migration
> issue in one place. It is intended as a teaching and demonstration artefact. A real enterprise
> app will typically have a much smaller subset of these issues — often just a handful of
> `android:exported` declarations, one or two `PendingIntent` flag fixes, and a notification
> permission guard. Do not be alarmed by the length of this list.

**Project state at time of scan:** `compileSdk 30 / targetSdk 30 / minSdk 26`
**Migration target:** `compileSdk 35 / targetSdk 35`
**Scan date:** 2026-03-29

---

## 1. BLOCKING ISSUES

Issues that cause **install failure or a runtime crash** when the target or compile SDK is raised.

---

### B-1 — Missing `android:exported` on five manifest components
**API level:** 31 | **Impact:** APK install blocked entirely

| Component | File | Line |
|---|---|---|
| `.MainActivity` | `AndroidManifest.xml` | 32 |
| `.AddItemActivity` | `AndroidManifest.xml` | 40 |
| `.datawedge.ScanReceiver` | `AndroidManifest.xml` | 52 |
| `.LowStockAlertReceiver` | `AndroidManifest.xml` | 61 |
| `.util.StockCheckReceiver` | `AndroidManifest.xml` | 68 |

**Fix:** Add `android:exported` to every component that has an `<intent-filter>`.
- `ScanReceiver` → `exported="true"` (receives cross-process DataWedge broadcasts)
- `LowStockAlertReceiver`, `StockCheckReceiver` → `exported="false"` (internal only)
- `MainActivity`, `AddItemActivity` → `exported="false"` (custom actions; not intended for external launch)

---

### B-2 — `PendingIntent` created with `flags = 0`
**API level:** 31 | **Impact:** `IllegalArgumentException` at runtime

| Site | File | Line |
|---|---|---|
| `scheduleDailyCheck` | `util/StockAlarmScheduler.kt` | 39 |
| `cancel` | `util/StockAlarmScheduler.kt` | 64 |
| Low-stock notification | `util/NotificationHelper.kt` | 57 |
| Export-complete notification | `util/NotificationHelper.kt` | 78 |

**Fix:** Add `PendingIntent.FLAG_IMMUTABLE` to every `PendingIntent.get*()` call. None of these
intents need to be mutable, so `FLAG_IMMUTABLE` is the correct choice in all four cases.

---

### B-3 — `Cipher.getInstance(TRANSFORMATION, "BC")` — BouncyCastle provider removed
**API level:** 31 | **Impact:** `NoSuchProviderException` at runtime

| Site | File | Line |
|---|---|---|
| `encrypt()` | `util/CryptoHelper.kt` | 37 |
| `decrypt()` | `util/CryptoHelper.kt` | 52 |

**Fix:** Remove the `"BC"` provider argument from both calls.
`Cipher.getInstance("AES/CBC/PKCS5Padding")` uses Conscrypt (the Android default), which fully
supports AES/CBC.

---

### B-4 — `AsyncTask` removed
**API level:** 33 | **Impact:** `NoClassDefFoundError` / crash on first database operation

**File:** `data/InventoryRepository.kt` lines 36–81 (five inner `AsyncTask` subclasses:
`FetchAllTask`, `FindByBarcodeTask`, `InsertItemTask`, `UpdateItemTask`, `CheckLowStockTask`)

**Fix:** Replace all five tasks with Kotlin coroutines. Introduce a `CoroutineScope` (or push DB
calls through a `ViewModel` with `viewModelScope`) and switch all database work to
`Dispatchers.IO`.

---

### B-5 — `Handler()` no-arg constructor removed
**API level:** 33 | **Impact:** runtime crash on splash screen launch

**File:** `SplashActivity.kt` line 42

**Fix:** Replace `Handler()` with `Handler(Looper.getMainLooper())`. Also consider migrating to
`androidx.core:core-splashscreen` — the system-provided splash is mandatory from API 31 and the
timed-delay pattern is redundant alongside it.

---

### B-6 — `setExactAndAllowWhileIdle()` without `canScheduleExactAlarms()` guard + missing permission
**API level:** 31 | **Impact:** `SecurityException` when the alarm is scheduled

**Files:** `util/StockAlarmScheduler.kt` line 53; `AndroidManifest.xml` (permission absent)

**Fix (two parts):**
1. Add to the manifest:
   ```xml
   <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
   ```
2. Guard the scheduling call:
   ```kotlin
   if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
       && !alarmManager.canScheduleExactAlarms()) {
       startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM))
       return
   }
   alarmManager.setExactAndAllowWhileIdle(...)
   ```

---

### B-7 — `registerReceiver()` without export flag
**API level:** 34 | **Impact:** `SecurityException` at runtime when `onResume` runs

**File:** `MainActivity.kt` line 117

**Fix:**
```kotlin
ContextCompat.registerReceiver(
    this, scanReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED
)
```
DataWedge scan broadcasts are targeted at this app via an explicit action; `NOT_EXPORTED` is the
correct flag.

---

## 2. REQUIRED CHANGES

Issues that cause **silent failures, denied permissions, or deprecated-API behaviour breaks**
when targeting higher SDK levels.

---

### R-1 — Notification trampoline (`LowStockAlertReceiver`)
**API level:** 31 | **Impact:** tapping the notification does nothing

**Files:**
- `LowStockAlertReceiver.kt` — entire class (calls `startActivity()` from a `BroadcastReceiver`
  triggered by a notification content intent)
- `NotificationHelper.kt` lines 52–57 (`PendingIntent` targeting the receiver)

**Fix:** Delete `LowStockAlertReceiver` entirely. Build a `PendingIntent` that points directly
at `MainActivity` and attach it via `NotificationCompat.Builder.setContentIntent()`.

---

### R-2 — Missing `POST_NOTIFICATIONS` runtime permission
**API level:** 33 | **Impact:** all notifications silently dropped

**Files:**
- `AndroidManifest.xml` (permission declaration absent)
- `NotificationHelper.kt` lines 71 and 91 (`manager.notify()` called without permission check)

**Fix:**
1. Add to the manifest:
   ```xml
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
   ```
2. Before calling `manager.notify()`, check
   `ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)`.
   Request the permission at first launch or before showing the first notification.

---

### R-3 — `READ/WRITE_EXTERNAL_STORAGE` permissions and public external storage write
**API level:** 30/33 | **Impact:** permission always denied; export writes fail or throw

**Files:**

| Issue | File | Line |
|---|---|---|
| `READ_EXTERNAL_STORAGE` permission declared | `AndroidManifest.xml` | 5 |
| `WRITE_EXTERNAL_STORAGE` permission declared | `AndroidManifest.xml` | 7 |
| `WRITE_EXTERNAL_STORAGE` runtime check | `ExportActivity.kt` | 56–65 |
| `Environment.getExternalStorageDirectory()` | `ExportActivity.kt` | 110 |
| `Environment.getExternalStorageDirectory()` | `StorageHelper.kt` | 22, 51 |
| Hardcoded `/sdcard/InventoryApp/photos` | `StorageHelper.kt` | 36 |

**Fix:**
- Remove both storage permissions from the manifest.
- Remove the `WRITE_EXTERNAL_STORAGE` permission-request code from `ExportActivity`.
- Replace storage paths:

  | Old path | New path |
  |---|---|
  | `Environment.getExternalStorageDirectory() + "/InventoryApp/exports"` | `context.getExternalFilesDir("exports")` |
  | `File("/sdcard/InventoryApp/photos")` | `context.getExternalFilesDir(Environment.DIRECTORY_PICTURES)` |
  | `Environment.getExternalStorageDirectory() + "/InventoryApp/temp"` | `context.cacheDir` or `context.getExternalFilesDir("temp")` |

  If CSV exports must be visible outside the app (e.g. for PC sync), use `MediaStore.Downloads`
  instead of `getExternalFilesDir`.

---

### R-4 — `startActivityForResult` / `onActivityResult` (deprecated)
**API level:** deprecated API 29 | **Impact:** future breakage; lint warnings

**Files:**

| Site | File | Line |
|---|---|---|
| Launch `AddItemActivity` (edit) | `MainActivity.kt` | 57 |
| Launch `AddItemActivity` (add) | `MainActivity.kt` | 65 |
| Launch `AddItemActivity` (scan) | `MainActivity.kt` | 136 |
| `onActivityResult` handler | `MainActivity.kt` | 75 |
| Gallery picker launch | `AddItemActivity.kt` | 83 |
| Camera launch | `AddItemActivity.kt` | 145 |
| `onActivityResult` handler | `AddItemActivity.kt` | 114 |

**Fix:** Replace every `startActivityForResult` call and its `onActivityResult` handler with
`registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result -> … }`.
For gallery picking, prefer `ActivityResultContracts.PickVisualMedia()`.

---

### R-5 — `onRequestPermissionsResult` (deprecated)
**API level:** deprecated API 29 | **Impact:** future breakage

**Files:** `AddItemActivity.kt` line 96; `ExportActivity.kt` line 71

**Fix:** Replace both overrides with
`registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> … }`.
The storage permission request in `ExportActivity` should be removed entirely (see R-3).

---

### R-6 — `onBackPressed()` override
**API level:** deprecated API 33 | **Impact:** future crash when override is removed from the framework

**File:** `MainActivity.kt` line 154

**Fix:**
```kotlin
onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
    override fun handleOnBackPressed() {
        // show exit dialog
    }
})
```

---

### R-7 — No edge-to-edge / `WindowInsetsCompat` handling
**API level:** 35 | **Impact:** content drawn behind system bars (status bar, navigation bar)

**Files:** `MainActivity.kt` (comment line 36), `AddItemActivity.kt` (comment line 42),
`ExportActivity.kt` (comment line 32)

`SettingsActivity.kt` already implements this correctly and can serve as the in-project reference.

**Fix:** In each affected `onCreate`, follow the `SettingsActivity` pattern:
```kotlin
WindowCompat.setDecorFitsSystemWindows(window, false)
ViewCompat.setOnApplyWindowInsetsListener(rootView) { v, insets ->
    val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
    v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
    insets
}
```

---

### R-8 — `SCHEDULE_EXACT_ALARM` auto-revoked on app update (API 34)
**API level:** 34 | **Impact:** alarm silently stops firing after any app update

**File:** `util/StockAlarmScheduler.kt` + calling activities

**Fix:** In `onResume` of the activity that owns alarm scheduling, re-check
`alarmManager.canScheduleExactAlarms()`. Reschedule if still granted; prompt the user to
re-grant if revoked.

---

### R-9 — `compileSdkVersion` / `targetSdkVersion` still at 30
**File:** `app/build.gradle` lines 7 and 13

**Fix:** Raise incrementally (30 → 31 → 33 → 34 → 35), validating each step before the next to
isolate regressions.

---

## 3. ZEBRA-SPECIFIC ISSUES

---

### Z-1 — `ScanReceiver` manifest registration missing `exported="true"`
**File:** `AndroidManifest.xml` line 52

DataWedge runs in a separate process (`com.symbol.datawedge`). The manifest-registered
`ScanReceiver` must be `android:exported="true"` or DataWedge cannot deliver broadcast intents
to it. This is the same root cause as B-1 but requires `true` (not `false`) because the sender
is an external process.

---

### Z-2 — Dynamic `registerReceiver` for DataWedge: correct flag required
**File:** `MainActivity.kt` line 117

The dynamically registered `ScanReceiver` should use `RECEIVER_NOT_EXPORTED`. DataWedge
broadcasts are delivered via an explicit action scoped to this app; the receiver does not need
to accept broadcasts from arbitrary senders. Fix is covered by B-7.

---

### Z-3 — DataWedge profile configuration: no issues found
`DataWedgeManager.kt` correctly uses the DataWedge Intent API (`com.symbol.datawedge.api.ACTION`
+ `SET_CONFIG`). EMDK is not used anywhere in the project. No changes required.

---

### Z-4 — AI Suite eligibility: not yet applicable
The Zebra AI Suite requires API 34+. Once the app reaches `targetSdk 34`, AI barcode recognition
(`EntityTrackerAnalyzer`) becomes available for advanced SKU capture scenarios. This is an
enhancement opportunity, not a migration requirement.

---

## 4. RECOMMENDED TESTS

| Change area | What to test | API level | Pass criteria |
|---|---|---|---|
| `android:exported` (B-1) | Fresh install of the APK | API 31 device/emulator | APK installs without `INSTALL_FAILED_*` error |
| `PendingIntent` flags (B-2) | Schedule alarm; trigger notification; tap notification | API 31 | No `IllegalArgumentException` in logcat; notification tap opens `MainActivity` |
| BouncyCastle removal (B-3) | Export a CSV (triggers encrypt); re-import (triggers decrypt) | API 31 | No `NoSuchProviderException`; file round-trips correctly |
| AsyncTask removal (B-4) | Load inventory; add item; edit item; trigger low-stock check | API 33 | All DB operations complete without `NoClassDefFoundError` |
| `Handler` fix (B-5) | Cold launch from launcher | API 33 | Splash transitions to `MainActivity` without crash |
| Exact alarm permission (B-6) | Enable notifications in settings; reboot device | API 31 | Low-stock alarm fires at 08:00; no `SecurityException` |
| `registerReceiver` flag (B-7) | Open `MainActivity`; scan a barcode | API 34 | Scan result received and processed; no `SecurityException` |
| Notification trampoline (R-1) | Trigger low-stock alert; tap the notification | API 31 | `MainActivity` opens; no silent failure |
| `POST_NOTIFICATIONS` (R-2) | Fresh install; enable notifications; trigger low-stock | API 33 | Permission dialog shown; notification appears after grant |
| Storage paths (R-3) | Export CSV; take a photo | API 30+ | Files written to `getExternalFilesDir()`; no `SecurityException` |
| `ActivityResultContracts` (R-4/R-5) | Add item; edit item; pick gallery image; take photo | Any | Results returned correctly; no deprecation crashes |
| Back gesture (R-6) | Press back / swipe back on `MainActivity` | API 33+ | Exit dialog appears via `OnBackPressedCallback` |
| Edge-to-edge (R-7) | Open each activity with gesture navigation enabled | API 35 | Content not obscured by status bar or navigation bar |
| Alarm revocation (R-8) | Update the APK; open settings | API 34 | App detects revocation and prompts user to re-grant |
| DataWedge end-to-end | Scan known barcode; scan unknown barcode | Zebra TC/MC device | Known → highlights item; unknown → opens `AddItemActivity` pre-filled |

---

## 5. SUGGESTED PHASE ORDER

The phases below map to the structure in `docs/Migration/migration-guide.md`.

| Step | Phase / Action | Rationale |
|---|---|---|
| 1 | **Phase 1 — Assessment**: run `./gradlew lint`, review `lint-results-debug.html` | Establishes a baseline before any code changes |
| 2 | **Raise `compileSdk` to 35** (leave `targetSdk` at 30 for now) | Unlocks lint warnings for all API levels without activating behaviour changes |
| 3 | **Phase 2a — targetSdk 30 → 31**: fix B-1, B-2, B-3, B-6, R-1, R-8 | All gate on crossing the API 31 boundary; fix together before bumping |
| 4 | Validate on API 31 emulator/device | Install, run all screens, review logcat for crashes |
| 5 | **Phase 2b — targetSdk 31 → 33**: fix B-4, B-5, R-2, R-6 | API 33 removes `AsyncTask` and no-arg `Handler`; notification permission also gates here |
| 6 | Validate on API 33 emulator/device | Verify DB operations, notifications, back handling |
| 7 | **Phase 2c — targetSdk 33 → 34**: fix B-7, R-3, R-4, R-5 | API 34 crashes on untagged `registerReceiver`; scoped storage enforcement tightens |
| 8 | Validate on API 34 Zebra device | Confirm DataWedge scanning, CSV export, photo capture |
| 9 | **Phase 2d — targetSdk 34 → 35**: fix R-7 (edge-to-edge on remaining activities) | API 35 enforces edge-to-edge; `SettingsActivity` already done, fix the other three |
| 10 | Validate on API 35 emulator | Check all activities for layout clipping against system bars |
| 11 | **Dependency bumps** (can run in parallel with phases 2a–2d): update `core-ktx`, `appcompat`, `material`, `lifecycle` to current stable versions; add `core-splashscreen` | Old 1.x versions lack `ContextCompat.registerReceiver` and `WindowCompat` APIs needed for the fixes above |
| 12 | Full regression on a Zebra TC/MC device at API 33+ | End-to-end: scan → lookup, scan → add, export CSV, settings → alarm, notifications |

> **Do not skip levels.** Going directly from targetSdk 30 to 35 activates all behaviour changes
> simultaneously and makes regressions very hard to isolate. One bump at a time is the correct
> strategy.

---

## Issue Summary

| ID | Severity | API | File | Description |
|---|---|---|---|---|
| B-1 | Blocking | 31 | `AndroidManifest.xml` | 5 components missing `android:exported` |
| B-2 | Blocking | 31 | `StockAlarmScheduler.kt`, `NotificationHelper.kt` | `PendingIntent` flags = 0 (4 sites) |
| B-3 | Blocking | 31 | `CryptoHelper.kt` | BouncyCastle provider removed |
| B-4 | Blocking | 33 | `InventoryRepository.kt` | `AsyncTask` removed (5 subclasses) |
| B-5 | Blocking | 33 | `SplashActivity.kt` | `Handler()` no-arg constructor removed |
| B-6 | Blocking | 31 | `StockAlarmScheduler.kt` + manifest | Exact alarm: no permission, no guard |
| B-7 | Blocking | 34 | `MainActivity.kt` | `registerReceiver` missing export flag |
| R-1 | Required | 31 | `LowStockAlertReceiver.kt`, `NotificationHelper.kt` | Notification trampoline blocked |
| R-2 | Required | 33 | Manifest + `NotificationHelper.kt` | `POST_NOTIFICATIONS` permission missing |
| R-3 | Required | 30/33 | `StorageHelper.kt`, `ExportActivity.kt`, manifest | Legacy storage permissions + hardcoded paths |
| R-4 | Required | 29+ | `MainActivity.kt`, `AddItemActivity.kt` | `startActivityForResult` deprecated (7 sites) |
| R-5 | Required | 29+ | `AddItemActivity.kt`, `ExportActivity.kt` | `onRequestPermissionsResult` deprecated |
| R-6 | Required | 33+ | `MainActivity.kt` | `onBackPressed()` deprecated |
| R-7 | Required | 35 | `MainActivity.kt`, `AddItemActivity.kt`, `ExportActivity.kt` | No edge-to-edge inset handling |
| R-8 | Required | 34 | `StockAlarmScheduler.kt` | Exact alarm permission auto-revoked on update |
| R-9 | Required | — | `build.gradle` | `compileSdk`/`targetSdk` at 30 |
| Z-1 | Zebra | 31 | `AndroidManifest.xml` | `ScanReceiver` needs `exported="true"` |
| Z-2 | Zebra | 33 | `MainActivity.kt` | Dynamic DataWedge receiver needs `NOT_EXPORTED` flag |
