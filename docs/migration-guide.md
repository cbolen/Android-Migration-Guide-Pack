# Zebra Android App Migration Guide: Android 11 → Android 15

For apps using DataWedge, EMDK, or other Zebra enterprise SDKs.

**Scope**: `targetSdk 30` → `targetSdk 35`
**Approach**: Bump `targetSdk` one major version at a time. Each bump activates a new set of behavior changes — incremental steps isolate regressions.

---

## Phase 1: Assessment

Before changing any code:

```bash
./gradlew lint
```

Review `app/build/reports/lint-results-debug.html` for:
- Deprecated API usages
- Missing `android:exported` attributes
- Unsafe `PendingIntent` flags
- `READ_EXTERNAL_STORAGE` usage

Also audit:
- All permissions in `AndroidManifest.xml`
- All background work (`Service`, `AlarmManager`, `AsyncTask`)
- All file read/write operations
- All `startActivityForResult` / `onBackPressed` usages
- All `BroadcastReceiver` registrations (DataWedge scan receivers included)

---

## Phase 2: Incremental targetSdk Bumps

### targetSdk 30 → 31 (Android 12)

**Breaking — causes crashes or install failures:**

**`android:exported` required on all manifest components with intent-filter**
```xml
<!-- Before — fails to install on API 31+ -->
<activity android:name=".MainActivity">
    <intent-filter>
        <action android:name="android.intent.action.MAIN" />
    </intent-filter>
</activity>

<!-- After -->
<activity android:name=".MainActivity" android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.MAIN" />
    </intent-filter>
</activity>
```

**`PendingIntent` must declare mutability flag**
```kotlin
// Before — throws exception on API 31+
val pending = PendingIntent.getActivity(context, 0, intent, 0)

// After
val pending = PendingIntent.getActivity(
    context, 0, intent, PendingIntent.FLAG_IMMUTABLE
)
```

**Splash screen enforced by system**

Remove custom splash `Activity`. Add `core-splashscreen`:
```gradle
implementation 'androidx.core:core-splashscreen:1.0+'
```
```xml
<!-- themes.xml -->
<style name="Theme.App.Starting" parent="Theme.SplashScreen">
    <item name="windowSplashScreenBackground">@color/brand_color</item>
    <item name="windowSplashScreenAnimatedIcon">@drawable/ic_launcher</item>
    <item name="postSplashScreenTheme">@style/Theme.App</item>
</style>
```
```kotlin
// In Activity.onCreate before setContentView
installSplashScreen()
```

**Behavior changes (non-crashing):**
- Overscroll glow replaced by stretch effect — custom `EdgeEffect` overrides may look wrong
- Dynamic Color (Material You) available — test with wallpaper theming enabled

---

### targetSdk 31 → 33 (Android 13)

**`POST_NOTIFICATIONS` is now a runtime permission**
```kotlin
val requestPermissionLauncher = registerForActivityResult(
    ActivityResultContracts.RequestPermission()
) { isGranted ->
    if (!isGranted) { /* show rationale or disable notification features */ }
}

if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    requestPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
}
```

**`READ_EXTERNAL_STORAGE` replaced by granular media permissions**
```xml
<!-- Remove: READ_EXTERNAL_STORAGE -->
<!-- Add for API 33+: -->
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"
    android:minSdkVersion="33" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"
    android:minSdkVersion="33" />
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO"
    android:minSdkVersion="33" />
<!-- Keep for API 32 and below: -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
```

**`AsyncTask` removed** — replace with coroutines:
```kotlin
// Before
class FetchTask : AsyncTask<Void, Void, Result>() {
    override fun doInBackground(vararg p: Void) = fetchData()
    override fun onPostExecute(result: Result) { updateUI(result) }
}

// After
viewModelScope.launch {
    val result = withContext(Dispatchers.IO) { fetchData() }
    updateUI(result)
}
```

**DataWedge receiver registration — new export flag required**
```kotlin
// Before (API < 33)
registerReceiver(scanReceiver, IntentFilter(SCAN_ACTION))

// After (API 33+)
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    registerReceiver(scanReceiver, IntentFilter(SCAN_ACTION), RECEIVER_NOT_EXPORTED)
} else {
    registerReceiver(scanReceiver, IntentFilter(SCAN_ACTION))
}
```

**Replace `onBackPressed()` with `OnBackPressedCallback`**
```kotlin
// Before — deprecated
override fun onBackPressed() {
    if (myCondition) handleBack() else super.onBackPressed()
}

// After
onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
    override fun handleOnBackPressed() {
        if (myCondition) handleBack() else {
            isEnabled = false
            onBackPressedDispatcher.onBackPressed()
        }
    }
})
```

**Subtle UI differences:**
- Clipboard read shows system toast — remove any custom "Copied!" toasts to avoid duplication
- Per-app language selector appears in system settings
- Predictive back gesture preview available (opt-in in Developer Options)

---

### targetSdk 33 → 34 (Android 14)

**Foreground service types strictly enforced**
```xml
<service
    android:name=".MyForegroundService"
    android:foregroundServiceType="dataSync"
    android:exported="false" />
```

Valid types: `camera`, `connectedDevice`, `dataSync`, `health`, `location`,
`mediaPlayback`, `mediaProjection`, `microphone`, `phoneCall`, `remoteMessaging`,
`shortService`, `specialUse`, `systemExempted`

**Partial photo access**
```xml
<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED"
    android:minSdkVersion="34" />
```
```kotlin
val hasFullAccess = ContextCompat.checkSelfPermission(context, READ_MEDIA_IMAGES) == PERMISSION_GRANTED
val hasPartialAccess = if (Build.VERSION.SDK_INT >= 34)
    ContextCompat.checkSelfPermission(context, READ_MEDIA_VISUAL_USER_SELECTED) == PERMISSION_GRANTED
else false

val canReadMedia = hasFullAccess || hasPartialAccess
```

**`SCHEDULE_EXACT_ALARM` revoked on upgrade**
```kotlin
val alarmManager = getSystemService(AlarmManager::class.java)
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    if (!alarmManager.canScheduleExactAlarms()) {
        startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM))
    }
}
```

**Zebra AI Suite becomes available at this API level** — if adding AI-based recognition (barcode, OCR, shelf) to your app, this is the minimum API level required.

---

### targetSdk 34 → 35 (Android 15)

**Edge-to-edge enforced — most impactful visual change**

Apps now draw behind system bars by default. Content will be clipped without inset handling.

```kotlin
// In Activity.onCreate, after setContentView
ViewCompat.setOnApplyWindowInsetsListener(binding.root) { view, windowInsets ->
    val insets = windowInsets.getInsets(WindowInsetsCompat.Type.systemBars())
    view.setPadding(insets.left, insets.top, insets.right, insets.bottom)
    WindowInsetsCompat.CONSUMED
}
```

For Jetpack Compose:
```kotlin
Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
    MyContent(modifier = Modifier.padding(innerPadding))
}
```

**Predictive back gesture enforced** — no longer opt-in. Ensure `OnBackPressedCallback` is used everywhere (see API 33 section above).

**Notification cooldown**
- If an app posts notifications too rapidly, the system automatically reduces their priority temporarily
- No API change required, but scan-heavy apps that fire a notification per barcode decode may see alerts silently downgraded
- Prefer updating a single persistent notification rather than posting a new one for each scan

**Background activity launch restrictions tightened**
- Apps can no longer start activities from the background without a visible notification or an active user-initiated task stack
- Affects workflow apps that launch screens from a `Service`, `BroadcastReceiver`, or `WorkManager` task
- If you need to surface UI from a background context, show a full-screen notification intent instead:
```kotlin
val fullScreenIntent = PendingIntent.getActivity(
    context, 0, Intent(context, AlertActivity::class.java), PendingIntent.FLAG_IMMUTABLE
)
val notification = NotificationCompat.Builder(context, CHANNEL_ID)
    .setFullScreenIntent(fullScreenIntent, true)
    .build()
```

**Private Space (behavioral — enterprise note)**
- Android 15 introduces Private Space, a secondary locked profile for sensitive personal apps
- For enterprise Zebra deployments, MDM can disable Private Space via policy — it is unlikely to be present on managed dedicated-use devices
- If your app could be installed into Private Space: it runs as an isolated profile, so DataWedge profile association must match the app's package name in that profile context

**Safer intents**
- Intents targeting a specific component must accurately match that component's `intent-filter` — action, category, and data must align
- Intents with no action no longer match any intent filter
- Audit any implicit intents used for internal app routing — convert to explicit intents where possible:
```kotlin
// Prefer explicit over implicit for internal components
val intent = Intent(context, ScanResultActivity::class.java)
context.startActivity(intent)
```
- DataWedge broadcast intents sent via `com.symbol.datawedge.api.ACTION` are explicit and unaffected — no change needed there

**TLS 1.0 and 1.1 restricted**
- Apps targeting Android 15 can no longer connect to servers using TLS 1.0 or 1.1 — connections will fail
- Affects enterprise apps connecting to internal servers, on-premise APIs, or legacy corporate infrastructure
- Verify all endpoints your app contacts support TLS 1.2 or higher; coordinate with IT/infrastructure teams if not

**BOOT_COMPLETED foreground service restrictions**
- Apps targeting Android 15 cannot launch certain foreground service types from a `BOOT_COMPLETED` receiver
- Affected types include `dataSync`, `mediaProcessing`, and others — `location` and `connectedDevice` are exempt
- If your app auto-starts a scanning or sync service on boot, use `WorkManager` with a `BOOT_COMPLETED` trigger instead:
```kotlin
// In your BroadcastReceiver
WorkManager.getInstance(context).enqueue(
    OneTimeWorkRequestBuilder<SyncWorker>().build()
)
```

**`elegantTextHeight` defaults to true**
- The `elegantTextHeight` attribute on `TextView` is now true by default for apps targeting Android 15
- Replaces the compact font metric with a taller, more readable one — increases line height for scripts with large vertical metrics
- Test all text-heavy screens, particularly on smaller Zebra displays (WS50/WS501) — rows and labels that were sized to compact font metrics may be clipped or overflow their containers

**`WorkManager` / `JobScheduler` constraints tightened**
- Jobs may be deferred more aggressively
- Test background sync after device is idle 15+ minutes

---

## Phase 3: Storage Migration

### Decision Tree

```
Does the file belong to your app only?
├── YES → use getExternalFilesDir() or filesDir
│          No permission needed. Deleted on uninstall.
└── NO → Is it media (image/video/audio)?
         ├── YES → use MediaStore
         └── NO → Is it a file the user selects?
                  ├── YES → use SAF (ACTION_OPEN_DOCUMENT)
                  └── NO → use MediaStore Downloads collection
```

### MediaStore write example (export to Downloads)
```kotlin
val values = ContentValues().apply {
    put(MediaStore.Downloads.DISPLAY_NAME, "export.csv")
    put(MediaStore.Downloads.MIME_TYPE, "text/csv")
    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
}
val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
uri?.let { contentResolver.openOutputStream(it)?.use { stream -> writeData(stream) } }
```

### SAF file picker example
```kotlin
val pickFile = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
    uri?.let { processFile(it) }
}
pickFile.launch(arrayOf("application/octet-stream"))
```

### Zebra SSM — when applicable
Starting at Android 11, scoped storage is already enforced — SSM is not needed for standard storage patterns. Use SSM only if:
- App runs exclusively on Zebra devices
- Files must be shared with other enterprise apps or MDM-pushed configs at deterministic paths
- Scripted/automated workflows require fixed file locations

---

## Phase 4: Jetpack Compatibility Libraries

```toml
# libs.versions.toml
[versions]
coreKtx = "1.13.1"
appcompat = "1.7.0"
activityKtx = "1.9.3"
material = "1.12.0"
workRuntime = "2.9.1"
splashscreen = "1.0.1"
datastorePreferences = "1.1.1"

[libraries]
androidx-core-ktx = { group = "androidx.core", name = "core-ktx", version.ref = "coreKtx" }
androidx-appcompat = { group = "androidx.appcompat", name = "appcompat", version.ref = "appcompat" }
androidx-activity-ktx = { group = "androidx.activity", name = "activity-ktx", version.ref = "activityKtx" }
material = { group = "com.google.android.material", name = "material", version.ref = "material" }
work-runtime-ktx = { group = "androidx.work", name = "work-runtime-ktx", version.ref = "workRuntime" }
core-splashscreen = { group = "androidx.core", name = "core-splashscreen", version.ref = "splashscreen" }
datastore-preferences = { group = "androidx.datastore", name = "datastore-preferences", version.ref = "datastorePreferences" }
```

| Concern | Library | Replaces |
|---|---|---|
| Back navigation | `androidx.activity:activity-ktx` | `onBackPressed()` |
| Permission requests | `androidx.activity:activity-ktx` | `onRequestPermissionsResult` |
| Photo picker | `androidx.activity:activity-ktx` `PickVisualMedia` | `ACTION_PICK` |
| Splash screen | `androidx.core:core-splashscreen` | Custom splash Activity |
| Window insets | `androidx.core:core-ktx` `WindowInsetsCompat` | Raw `WindowInsets` |
| Background work | `androidx.work:work-runtime-ktx` | `AsyncTask`, `IntentService` |
| Preferences | `androidx.datastore:datastore-preferences` | `SharedPreferences` |
| Notifications | `androidx.core:core-ktx` `NotificationCompat` | Direct `Notification.Builder` |

---

## Phase 5: Subtle UI & Behavior Differences

### Layout / Visual
- **Edge-to-edge (API 35)**: Bottom nav, FABs, input fields hidden behind nav bar — add inset padding
- **Dynamic Color**: Hardcoded colors may clash with wallpaper palette — test with Dynamic Color enabled
- **Splash screen double-flash**: Custom splash Activity still present on API 31+ shows two splashes — remove it
- **Text scaling (API 33+)**: Non-linear scaling above 100% — test at 130%, 200% font scale
- **Stretch overscroll (API 31+)**: Custom `EdgeEffect` no longer shows glow

### Behavioral
- **Clipboard toast (API 33+)**: System shows toast on clipboard read — remove custom "Copied!" toasts
- **Back gesture vs button**: Predictive back preview only shows on gesture nav — test both nav modes
- **"Only this time" permission**: Camera/mic/location grants are session-only — handle re-request gracefully
- **Keyboard insets (API 30+)**: Migrate `adjustResize` window soft input mode to `WindowInsetsAnimationCompat`

### Zebra-Specific
- **DataWedge receiver (API 33+)**: `RECEIVER_NOT_EXPORTED` flag required — see `datawedge-intents-ref.md`
- **EMDK service binding (API 34+)**: Verify `EMDKManager.getEMDKManager()` still binds correctly after foreground service type enforcement
- **DataWedge profile association**: Profile package name must match app package exactly — verify after signing config changes

---

## Phase 6: System UI Behavior Changes by API Level

These changes require no code fix but affect UX, user perception, and QA sign-off. Each one can generate "is this a bug?" questions if the team isn't prepared.

---

### Android 12 (API 31)

**Privacy indicator dot (mic/camera)**
- A green dot appears in the top-right corner of the status bar whenever an app accesses the microphone or camera
- Users cannot disable it — it is a system indicator
- **Impact**: Users may ask why the dot appears during barcode scanning (if using camera-based scanning) or voice features. Prepare UX copy or an in-app explainer if relevant
- **Zebra note**: DataWedge scanner use does NOT trigger the mic/camera indicator — it accesses the scanner hardware directly, not the camera API
- **Zebra enterprise deployment note**: If the device runs Zebra Enterprise Home Screen (EHS) with the status bar hidden (`statusBarState = hide`), the privacy indicator is suppressed as a side effect. Zebra MX UI Manager can also disable the status bar more surgically via StageNow or MDM without full EHS lockdown. For dedicated-use deployments (warehouse, retail, healthcare) where the status bar is already hidden, the privacy dot is typically a non-issue

**Toast redesign**
- Full-width toasts replaced with compact floating toasts
- Toasts from background apps are blocked entirely
- **Impact**: Any toast shown from a background `Service` will be silently dropped. Move user-facing messages to notifications or foreground UI

**Notification tray visual changes**
- Notification cards have rounded corners and updated padding
- Custom `RemoteViews` notifications are re-styled by the system — custom backgrounds may look wrong
- **Impact**: Test all notification styles, especially custom layouts

**Overscroll stretch effect**
- Replaces the blue glow with a rubber-band stretch animation
- Custom `EdgeEffect` subclasses no longer apply the glow — the stretch effect takes over
- **Impact**: Visual regression if your app customised the overscroll glow for branding

**Approximate location**
- Users can grant approximate location (`ACCESS_COARSE_LOCATION`) even when the app requests precise location
- **Impact**: If your app requires precise location, check `LocationManager.isProviderEnabled` and handle the degraded case

---

### Android 13 (API 33)

**Clipboard access toast**
- System shows a toast ("App pasted from your clipboard") whenever an app reads clipboard content
- Cannot be suppressed by the app
- **Impact**: If your app shows its own "Pasted!" confirmation, users will see two toasts. Remove your custom toast

**Permission dialog UI**
- "Allow" / "Deny" buttons replaced with "Allow only while using the app" / "Don't allow" for sensitive permissions
- Rationale dialogs look different — test that your rationale UI doesn't visually conflict with the system dialog

**Themed app icons**
- On supported launchers, app icons can be tinted to match the system wallpaper colour (monochrome adaptive icon)
- **Impact**: If you haven't provided a `mipmap/ic_launcher_monochrome` resource, the system generates one automatically — it may look poor. Add a clean monochrome version

**Media picker (Photo Picker)**
- System provides a new bottom-sheet media picker when using `PickVisualMedia` contract
- Users can grant access to selected photos only, rather than all photos
- **Impact**: If your app assumes it can access all photos after a grant, it will miss files the user didn't select. Use the URI returned from the picker directly

**Notification permission dialog**
- `POST_NOTIFICATIONS` triggers a system dialog — the first time only
- If denied and `shouldShowRequestPermissionRationale` returns `false`, the user must go to Settings
- **Impact**: QA must test the full denial flow, not just the grant flow

---

### Android 14 (API 34)

**Partial photo/video access UI**
- When requesting `READ_MEDIA_IMAGES`, users see a new option: "Select photos and videos" (partial access) in addition to "Allow all" and "Don't allow"
- The app receives `READ_MEDIA_VISUAL_USER_SELECTED` permission, not full `READ_MEDIA_IMAGES`
- **Impact**: File pickers that enumerate all media will only see the user-selected subset. Use the system Photo Picker to avoid this complexity

**Health Connect consent screen**
- New dedicated Health Connect permission UI replaces inline permission dialogs
- **Impact**: Relevant only if your app reads health/fitness data

**Back arrow predictive preview**
- Predictive back gesture shows a preview of the destination screen behind the current one as the user swipes
- **Impact**: If your destination Activity/Fragment has a slow `onCreate` or no background set, the preview looks blank or glitchy. Ensure screens render quickly and have a proper background colour

**Exact alarm permission revoked on upgrade**
- `SCHEDULE_EXACT_ALARM` is revoked when the app is updated if the user had previously denied it
- System shows no UI — the permission is silently gone
- **Impact**: Scheduled jobs that rely on exact timing silently stop working after an OTA update. Add a check on `onResume` and prompt the user to re-grant if needed

---

### Android 15 (API 35)

**Edge-to-edge enforced — status bar and nav bar overlap content**
- The system no longer reserves space for status/navigation bars by default
- **Impact**: The single most common visual regression on API 35. Bottom navigation bars, FABs, and input fields sit behind the gesture nav bar unless inset padding is applied. See `examples/edge-to-edge-insets.kt`

**Predictive back enforced for all apps**
- Predictive back is no longer opt-in — all apps get it
- **Impact**: The destination preview appears regardless of `android:enableOnBackInvokedCallback`. If your back navigation has visual glitches (no background, partial state), users will see them during the swipe before completing the gesture

**Health & fitness permissions consolidated**
- `BODY_SENSORS` and related permissions moved under Health Connect flow
- **Impact**: Affects apps reading heart rate, step count, etc.

**Large screen / foldable**
- Apps are expected to handle multi-window and foldable states gracefully
- **Impact**: On Zebra foldable/large-screen devices (ET series), test that the camera viewfinder and scan overlays resize correctly

---

### Cross-Version Notes

**"Only this time" permission (API 30+)**
- Location, microphone, and camera grants can be session-only
- On next app launch the permission is revoked silently
- **Impact**: Apps that cache the granted state and skip the permission check on resume will fail silently. Always check permission state in `onResume`

**System back gesture vs hardware back button**
- Predictive back preview only triggers on gesture navigation, not the 3-button hardware back button
- **Impact**: Animations and transitions tied to back navigation may behave differently between the two. Test both navigation modes

**Notification channel importance — user can downgrade**
- Users can change notification channel importance to `NONE`, `LOW`, or `MIN` at any time from Settings
- **Impact**: Critical enterprise alerts (e.g., low battery, connectivity lost) may be silenced by the user. Design alerts to degrade gracefully and provide an in-app fallback

---

## Phase 7: Testing Checklist

### Emulator Matrix
| API | Android | Key Verification |
|---|---|---|
| 30 | Android 11 | Scoped storage, package visibility |
| 31 | Android 12 | `exported` flag, `PendingIntent`, splash |
| 33 | Android 13 | Notification permission, granular media, `AsyncTask` removed, DataWedge receiver flag |
| 34 | Android 14 | Foreground service types, partial photo access |
| 35 | Android 15 | Edge-to-edge, predictive back enforced |

### DataWedge / Scanning
- [ ] Scan received correctly via BroadcastReceiver
- [ ] Receiver registered with `RECEIVER_NOT_EXPORTED` on API 33+
- [ ] DataWedge profile created/switched via Intent API
- [ ] SOFT_SCAN_TRIGGER starts and stops scan
- [ ] App unregisters receiver in `onPause` — no duplicate scans after resume
- [ ] EMDK `EMDKManager` releases correctly on `onPause` / `onDestroy`

### Storage
- [ ] Create file in `getExternalFilesDir()` — no permission prompt
- [ ] Export file to `Downloads/` via MediaStore
- [ ] Import file via SAF `ACTION_OPEN_DOCUMENT`
- [ ] Share file via `FileProvider`
- [ ] Revoke storage permission mid-session — app handles gracefully

### Permissions
- [ ] Fresh install — all permission dialogs appear with correct rationale
- [ ] Upgrade from old APK — no permission regressions
- [ ] "Deny and don't ask again" — app shows settings deep-link
- [ ] `POST_NOTIFICATIONS` denied — no crash, notifications gracefully disabled

### UI
- [ ] Font scale 100%, 130%, 200% — no text clipped or overlapping
- [ ] Gesture navigation + 3-button navigation — bottom content visible in both
- [ ] Edge-to-edge: FAB and bottom nav not hidden behind nav bar
- [ ] Back: hardware button, gesture swipe, predictive back (Developer Options)
- [ ] Rotate device mid-operation — no state loss

---

## Phase 7: Release Checklist

- [ ] `compileSdk` = 35
- [ ] `targetSdk` = 35
- [ ] All `android:exported` attributes set on components with `intent-filter`
- [ ] All `PendingIntent` calls have `FLAG_IMMUTABLE` or `FLAG_MUTABLE`
- [ ] `POST_NOTIFICATIONS` requested at appropriate UX moment
- [ ] No `READ_EXTERNAL_STORAGE` without `maxSdkVersion="32"` guard
- [ ] No `onBackPressed()` overrides — replaced with `OnBackPressedCallback`
- [ ] No `startActivityForResult` / `onActivityResult`
- [ ] No `AsyncTask`
- [ ] Foreground service types declared in manifest
- [ ] Edge-to-edge insets handled in all screens
- [ ] Splash `Activity` removed
- [ ] DataWedge receivers use `RECEIVER_NOT_EXPORTED` on API 33+
- [ ] Lint passes with no `Error` severity issues

---

## Appendix: Zebra Device-Specific Guidance

### WS50 / WS501 — Square Display

The WS50 and WS501 are wearable computers with a square display. They shipped with Android 11 (WS50) and Android 13 (WS501). Both devices present the same square display characteristics but there are meaningful API behavior differences between Android 13 and Android 14 that affect these devices.

---

#### Square Display — Core Behaviour (All Android Versions)

On a square display, `configuration.orientation` returns `ORIENTATION_UNDEFINED` (0) — not `ORIENTATION_PORTRAIT` (1) or `ORIENTATION_LANDSCAPE` (2). This is consistent across all Android versions.

**Any code that uses `if/else` with only portrait and landscape cases will silently fall through to the wrong branch on a square display.**

Always handle all three cases:
```kotlin
// Handles square/undefined displays correctly
val label = when (orientation) {
    Configuration.ORIENTATION_PORTRAIT  -> "Portrait"
    Configuration.ORIENTATION_LANDSCAPE -> "Landscape"
    else                                -> "Square"
}
```

**Orientation locking** — do not use `configuration.orientation` inside rotation-based logic. Map rotation directly to the lock constant, which is always unambiguous regardless of display shape:
```kotlin
val lock = when (rotation) {
    Surface.ROTATION_0   -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    Surface.ROTATION_90  -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
    Surface.ROTATION_180 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
    Surface.ROTATION_270 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
    else                 -> ActivityInfo.SCREEN_ORIENTATION_LOCKED
}
```

---

#### Android 13 (API 33) on WS50 / WS501

**Display metrics**
- `WindowManager.defaultDisplay` and `Display.getRealSize()` still work but are deprecated — begin migrating to `WindowMetrics`
- `configuration.orientation` returns `ORIENTATION_UNDEFINED` on square display — consistent with all prior versions

**Receiver registration change (applies to all Zebra devices)**
- DataWedge scan receivers must use `RECEIVER_NOT_EXPORTED` flag — see `datawedge-intents-ref.md`
- This affects WS50/WS501 identically to other Zebra devices

**Foreground services**
- `foregroundServiceType` is recommended but not yet strictly enforced
- Plan the type declaration now before upgrading to A14

**Back navigation**
- `onBackPressed()` deprecated — migrate to `OnBackPressedCallback`
- On wearable form factors, hardware back button behaviour should be tested explicitly as gesture navigation may not be available

---

#### Android 14 (API 34) on WS50 / WS501 — Key Changes from A13

**Display metrics — `getRealSize()` and `getRealMetrics()` deprecated (all devices)**

`Display.getRealSize()` and `Display.getRealMetrics()` were deprecated in API 31 (Android 12) and should not be used in new development. Verify current removal status against the Android API reference before upgrading — the timeline for hard removal may vary. Migrate to `WindowMetrics` now regardless of removal status, as lint will flag these as errors and behaviour on non-standard displays (including square displays) is unreliable.

This affects all Android devices, not just WS50/WS501 — it is called out here because display dimension APIs are particularly relevant when dealing with square display detection.

```kotlin
// Deprecated since API 31 — avoid
@Suppress("DEPRECATION")
windowManager.defaultDisplay.getRealSize(point)

// CORRECT for A14+
val bounds = windowManager.currentWindowMetrics.bounds
val width = bounds.width()
val height = bounds.height()

// Square display detection using WindowMetrics (A14+)
val ratio = width.toFloat() / height.toFloat()
val isSquare = ratio in 0.95f..1.05f
```

**Foreground service types strictly enforced**

On A14, a foreground service without a declared `foregroundServiceType` crashes at runtime. For WS50/WS501 apps that run scanning or data collection services:
```xml
<service
    android:name=".ScanService"
    android:foregroundServiceType="dataSync"
    android:exported="false" />
```

**`SCHEDULE_EXACT_ALARM` revoked on app upgrade**
- Particularly relevant for WS50/WS501 workflow apps that schedule exact-time data sync or shift reminders
- Add a check in `onResume` and handle the case where the permission has been silently revoked

**Partial media access UI**
- Users on A14 see a "Select photos" partial access option — relevant for WS50/WS501 apps that import reference images or product photos
- Use the system Photo Picker to avoid having to handle partial vs full access

**Predictive back available**
- Predictive back gesture preview is available on A14 as opt-in
- On wearable form factors verify the destination preview renders correctly — slow `onCreate` or missing background colour in destination screens is visible to the user during the swipe

---

#### Detecting a Square Display (A13 and A14+)

```kotlin
fun Context.isSquareDisplay(): Boolean {
    val (width, height) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val bounds = (getSystemService(Context.WINDOW_SERVICE) as WindowManager)
            .currentWindowMetrics.bounds
        bounds.width() to bounds.height()
    } else {
        @Suppress("DEPRECATION")
        val display = (getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay
        val size = android.graphics.Point()
        @Suppress("DEPRECATION")
        display.getSize(size)
        size.x to size.y
    }
    val ratio = width.toFloat() / height.toFloat()
    return ratio in 0.95f..1.05f
}
```

---

#### Layout Guidance for Square Displays

- Do not use `ORIENTATION_PORTRAIT` or `ORIENTATION_LANDSCAPE` as a guard for showing/hiding UI — use display size or aspect ratio
- `fillMaxSize()` (Compose) and `match_parent` (Views) work correctly on square displays
- `WindowSizeClass` from `androidx.window:window` provides `COMPACT`/`MEDIUM`/`EXPANDED` breakpoints that are reliable on square displays — prefer it over `configuration.orientation` for adaptive layout decisions
- Avoid fixed-width panels or side navigation that assume a landscape long axis exists

```kotlin
val windowSizeClass = calculateWindowSizeClass(this)
val isCompact = windowSizeClass.widthSizeClass == WindowWidthSizeClass.COMPACT
```

---

#### Creating a Square Display Emulator AVD

1. Android Studio → Device Manager → Create Virtual Device
2. Choose "New Hardware Profile"
3. Set Screen Size to `2.2"`, Resolution to `480 x 480`
4. Leave orientation as default
5. Use this AVD to reproduce WS50/WS501 display issues before testing on physical hardware

---

#### WS50 / WS501 General Notes

- Input is primarily hardware buttons and touch — ensure all interactive elements meet minimum 48dp touch target size
- Small screen size means aggressive text truncation — test with `fontScale = 1.3`
- DataWedge is available — same intent patterns as all other Zebra devices
- Avoid hardcoded pixel values — use `dp`/`sp` throughout; screen density may differ from standard phone values

---

## References

- [Android 12 behavior changes](https://developer.android.com/about/versions/12/behavior-changes-12)
- [Android 13 behavior changes](https://developer.android.com/about/versions/13/behavior-changes-13)
- [Android 14 behavior changes](https://developer.android.com/about/versions/14/behavior-changes-14)
- [Android 15 behavior changes](https://developer.android.com/about/versions/15/behavior-changes-15)
- [DataWedge Intent API](https://techdocs.zebra.com/datawedge/latest/guide/api/)
- [EMDK for Android](https://techdocs.zebra.com/emdk-for-android/latest/guide/about/)
- [Zebra AI Suite SDK](https://techdocs.zebra.com/ai-datacapture/latest/about/)
- [Zebra SSM](https://techdocs.zebra.com/mx/ssmmgr/)
- [WindowInsetsCompat guide](https://developer.android.com/develop/ui/views/layout/edge-to-edge)