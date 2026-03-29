# Zebra Android App Migration Guide: Android 11 → Android 15

For apps using DataWedge, EMDK, or other Zebra enterprise SDKs.

**Scope**: `targetSdk 30` → `targetSdk 35`
**Approach**: Bump `targetSdk` one major version at a time. Each bump activates a new set of behavior changes — incremental steps isolate regressions.

---

## Phase 0: AI-Assisted Discovery

If you are using an AI coding assistant (Claude Code, Cursor, GitHub Copilot), run this prompt first. It produces a full migration plan with no code changes so you know the complete scope before automation begins.

> **Claude Code / Cursor / Copilot**: these tools have direct access to your project files — "scan this project" reads every file automatically. No pasting required.
>
> **Chat tools (Claude.ai, ChatGPT, Gemini)**: paste `AndroidManifest.xml`, `build.gradle`, and your key source files into the conversation first, then replace "scan this project" with "review the files I have pasted above".

```
Read CLAUDE.md for Zebra platform rules and docs/migration/migration-guide.md for the
full A11–A15 change reference.

Then scan this entire Android project — AndroidManifest.xml, all Kotlin/Java source
files, build.gradle / build.gradle.kts, and libs.versions.toml if present.

Produce a migration plan with the following sections:

1. BLOCKING ISSUES (causes install failure or runtime crash)
   - List each issue, the file and line, the API level that breaks it, and the fix needed

2. REQUIRED CHANGES (behaviour breaks silently or permission is denied)
   - List each issue, the file and line, the API level that enforces it, and the fix needed

3. ZEBRA-SPECIFIC ISSUES
   - DataWedge receiver registration, EMDK lifecycle, storage patterns, AI Suite eligibility

4. RECOMMENDED TESTS
   - Per change area: what to test, on which API level, and what a pass looks like

5. SUGGESTED PHASE ORDER
   - Recommend which of the migration phases (1–12) in docs/how-to-use.md apply to this
     project and in what order

Do not make any changes. Output the plan only.
```

Review and confirm the plan before proceeding to Phase 1.

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

**Bluetooth permissions restructured**

Android 12 replaces the old location-based Bluetooth permission model with dedicated permissions. Apps no longer need `ACCESS_FINE_LOCATION` just to scan for paired devices.

```xml
<!-- Remove: BLUETOOTH, BLUETOOTH_ADMIN (or scope with maxSdkVersion) -->
<!-- Add for API 31+: -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:minSdkVersion="31" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"
    android:minSdkVersion="31" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"
    android:minSdkVersion="31" />
<!-- Keep for API 30 and below: -->
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />
```

Request `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` at runtime like any other dangerous permission. If your scan does not use scan results to derive physical location, add `android:usesPermissionFlags="neverForLocation"` to `BLUETOOTH_SCAN` to avoid needing location permission.

**Exact alarm permission — introduced here (`SCHEDULE_EXACT_ALARM`)**

Starting with Android 12, `AlarmManager.setExact*()` and `setAlarmClock()` require the `SCHEDULE_EXACT_ALARM` permission. The permission is granted by default on first install but can be revoked by the user (and is silently revoked on app upgrade starting A14 — see that section).

```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

```kotlin
// Check before scheduling
val alarmManager = getSystemService(AlarmManager::class.java)
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    if (!alarmManager.canScheduleExactAlarms()) {
        startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM))
        return
    }
}
alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMs, pendingIntent)
```

**Notification trampoline restrictions**

Apps targeting API 31+ can no longer use a `Service` or `BroadcastReceiver` as an intermediary to launch an `Activity` when a notification is tapped. The activity must be started directly from the `PendingIntent` attached to the notification.

```kotlin
// Before — launched Activity from a BroadcastReceiver triggered by notification tap
// This is now blocked on API 31+

// After — set PendingIntent directly on the notification action
val intent = Intent(context, ScanResultActivity::class.java)
val pendingIntent = PendingIntent.getActivity(
    context, 0, intent, PendingIntent.FLAG_IMMUTABLE
)
NotificationCompat.Builder(context, CHANNEL_ID)
    .setContentIntent(pendingIntent)  // Direct activity launch — allowed
    .build()
```

**Foreground service launch from background blocked**

Apps targeting API 31+ cannot start a foreground service while the app is in the background. Use `WorkManager` for deferred background work, or ensure the service is started while the app is in the foreground.

```kotlin
// If you must start a foreground service from a background context (e.g., a scheduled job):
// Use WorkManager and let it manage the foreground service lifecycle instead
val request = OneTimeWorkRequestBuilder<MyWorker>()
    .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
    .build()
WorkManager.getInstance(context).enqueue(request)
```

**BouncyCastle cryptography implementations removed**

Android 12 removes the BouncyCastle implementations of many cryptographic algorithms that were previously deprecated. If your app (or any third-party library it uses) directly references `org.bouncycastle.*` classes or uses algorithms like `PBKDF2WithHmacSHA1` via a named provider, it will throw `NoSuchAlgorithmException` or `NoSuchProviderException` at runtime.

```kotlin
// Broken on API 31+ — explicit BouncyCastle provider
val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding", "BC")  // throws on A12

// Correct — use the default provider (backed by Conscrypt on Android)
val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
```

Audit your dependencies: libraries like older versions of `bcprov-jdk15on`, Spongy Castle wrappers, or any library that explicitly specifies `"BC"` as the provider will break. Update to current versions of those libraries, or switch to Android's Conscrypt/standard JCA APIs.

**Behavior changes (non-crashing):**
- Overscroll glow replaced by stretch effect — custom `EdgeEffect` overrides may look wrong
- Dynamic Color (Material You) available — test with wallpaper theming enabled
- Root launcher activities no longer finish on back press — they move to the background instead; don't rely on `Activity.finish()` being called on back from a root launcher activity

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

**`BluetoothAdapter.enable()` and `disable()` always return `false`**

Apps targeting API 33+ can no longer programmatically enable or disable Bluetooth — these methods are silently no-ops and return `false`. Direct the user to system settings instead.

```kotlin
// Broken on API 33+ targets — returns false, does nothing
bluetoothAdapter.enable()

// Correct — prompt the user
if (!bluetoothAdapter.isEnabled) {
    startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
}
```

**`NEARBY_WIFI_DEVICES` permission for Wi-Fi scanning**

Apps targeting API 33+ that use Wi-Fi peer-to-peer, Wi-Fi Aware, or access point APIs no longer need `ACCESS_FINE_LOCATION` for those operations — use `NEARBY_WIFI_DEVICES` instead.

```xml
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES"
    android:usesPermissionFlags="neverForLocation"
    android:minSdkVersion="33" />
```

**`WebView.setForceDark()` deprecated**

Apps targeting API 33 should not call `setForceDark()` — the WebView now respects the app's theme and applies dark mode via the `prefers-color-scheme` CSS media query automatically.

```kotlin
// Deprecated on API 33+ — remove
WebSettingsCompat.setForceDark(webView.settings, WebSettingsCompat.FORCE_DARK_ON)

// Instead, set your app theme to DayNight and WebView handles it automatically
// In themes.xml: parent="Theme.MaterialComponents.DayNight"
```

**`USE_EXACT_ALARM` — install-time permission for alarm/calendar apps**

If your app's primary purpose is an alarm or calendar, you can declare `USE_EXACT_ALARM` instead of `SCHEDULE_EXACT_ALARM`. It is granted automatically at install and cannot be revoked by the user — but it is restricted to alarm/calendar use cases and will be reviewed by Google Play.

```xml
<!-- Only if your app IS a clock/alarm/calendar app -->
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

For general enterprise apps (scan, sync, workflow), stick with `SCHEDULE_EXACT_ALARM` and the `canScheduleExactAlarms()` check described in the A12 section.

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
`mediaPlayback`, `mediaProjection`, `mediaProcessing` *(added A15)*, `microphone`,
`phoneCall`, `remoteMessaging`, `shortService`, `specialUse`, `systemExempted`

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

**`SCHEDULE_EXACT_ALARM` silently revoked on app upgrade**

`SCHEDULE_EXACT_ALARM` was introduced in A12 (see that section). Starting with A14, the permission is silently revoked when the app is updated — the user is not prompted, and no broadcast is sent.

```kotlin
// Add this check to onResume — the permission may have disappeared after an OTA or app update
val alarmManager = getSystemService(AlarmManager::class.java)
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    if (!alarmManager.canScheduleExactAlarms()) {
        startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM))
    }
}
```

**Safer intents — implicit intents to internal components blocked**

Apps targeting API 34 can no longer send implicit intents to components declared as non-exported within their own app. Use explicit intents for all internal routing.

```kotlin
// Blocked on API 34+ — implicit intent matching internal non-exported component
startActivity(Intent("com.myapp.ACTION_SCAN_RESULT"))

// Correct — explicit intent
startActivity(Intent(context, ScanResultActivity::class.java))
```

**`USE_FULL_SCREEN_INTENT` restricted to alarm and calling apps**

Apps targeting API 34 that are not alarm clock or calling apps lose the `USE_FULL_SCREEN_INTENT` permission automatically. Full-screen intents posted by other apps are displayed as standard expanded notifications instead.

```kotlin
// Check whether full-screen intents are still permitted before posting
val notificationManager = getSystemService(NotificationManager::class.java)
if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
    notificationManager.canUseFullScreenIntent()) {
    // attach full-screen intent
} else {
    // fall back to high-priority heads-up notification
}
```

For enterprise alert scenarios (low battery, connectivity lost, critical workflow failures), replace full-screen intents with high-priority `IMPORTANCE_HIGH` notification channels — these produce heads-up notifications without requiring the permission.

**Background activity launch restrictions (introduced here, tightened further in A15)**

Apps targeting API 34 cannot start activities from the background unless they hold a specific exemption token (e.g., a `PendingIntent` granted by the system, an active notification full-screen intent, or a visible bound service). See the A15 section for additional restrictions added there.

**Safer dynamic code loading**

Apps targeting API 34 that dynamically load DEX files (via `DexClassLoader` or similar) must ensure those files are read-only before loading. Writable files are rejected at runtime.

```kotlin
val dexFile = File(context.filesDir, "plugin.dex")
dexFile.setReadOnly() // required before loading on API 34+
val classLoader = DexClassLoader(dexFile.absolutePath, null, null, classLoader)
```

**Zip path traversal prevention**

`ZipFile` and `ZipInputStream` now throw `ZipException` for entries whose names contain path traversal sequences (e.g., `../`). If your app unzips files received from external sources or MDM pushes, validate entry names before extraction.

```kotlin
fun safeExtract(zip: ZipInputStream, destDir: File) {
    var entry = zip.nextEntry
    while (entry != null) {
        val target = File(destDir, entry.name).canonicalFile
        if (!target.path.startsWith(destDir.canonicalPath + File.separator)) {
            throw SecurityException("Zip path traversal: ${entry.name}")
        }
        // extract...
        entry = zip.nextEntry
    }
}
```

**Context-registered broadcasts queued when app is cached**

Implicit broadcasts sent to context-registered receivers are queued (not delivered) while the app is in the cached state. Delivery resumes when the app returns to the foreground.

- **Impact for DataWedge**: DataWedge scan result broadcasts are explicit (targeted at your registered receiver), so they are not affected by this queueing. However, any implicit system broadcasts your app listens for (connectivity changes, battery state, etc.) may arrive in a burst when the app resumes
- Design broadcast handlers to be idempotent — processing the same broadcast twice should produce the same result

**`MediaProjection` — user consent required per capture session**

Apps targeting API 34 must request user consent every time a screen capture session starts — the previous one-time grant no longer carries over.

**`JobScheduler` / `WorkManager` reinforcement**

Jobs that exceed their granted main-thread time now trigger an ANR. Ensure all `Worker.doWork()` implementations run I/O and processing on background threads and do not block the main thread.

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

**Safer intents (extended from A14)**
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

**16 KB memory page size — prepare native code now**

Android 15 adds support for 16 KB memory page sizes. No current Zebra devices use a 16 KB page size, so this is not an immediate runtime concern for Zebra-deployed apps. However, Google Play now requires that apps with native code support 16 KB page sizes, so this matters if your app is distributed via Play Store. It is also preparation for future Android devices broadly.

Zebra AI Suite already ships with 16 KB-compatible builds. For your own native code or third-party native SDKs, audit and rebuild before Play Store submission:

```bash
# Check alignment of each .so — must show 16384 (0x4000)
readelf -l libmylibrary.so | grep LOAD
```

```cmake
# CMakeLists.txt — add to native targets
target_link_options(mylib PRIVATE "-Wl,-z,max-page-size=16384")
```

Audit every `.so` in your APK — third-party native SDKs (PDF renderers, crypto libraries, barcode engines) each need their own 16 KB-aligned build from the vendor.

**Audio focus restrictions**

Apps targeting API 35 must be in the foreground or running an audio-related foreground service to request audio focus. Background audio focus requests are denied.

- **Impact**: Any scan beep, voice prompt, or audio alert triggered from a background `Service` or `BroadcastReceiver` may be silently denied
- Move audio playback into a foreground service with type `mediaPlayback`, or ensure audio is always triggered while the app is in the foreground
- DataWedge's built-in scan beep is handled by the DataWedge service itself and is unaffected — this only applies to audio your app plays directly

**`Configuration` no longer excludes system bars**

`Configuration.screenWidthDp` and `Configuration.screenHeightDp` now include the area occupied by system bars. Previously these values reflected the space available after subtracting system bar insets.

```kotlin
// Broken on API 35+ — screenWidthDp now includes system bar space
val widthPx = resources.configuration.screenWidthDp * density

// Correct — use WindowMetrics for available content area
val windowMetrics = windowManager.currentWindowMetrics
val insets = windowMetrics.windowInsets.getInsetsIgnoringVisibility(
    WindowInsetsCompat.Type.systemBars()
)
val availableWidth = windowMetrics.bounds.width() - insets.left - insets.right
val availableHeight = windowMetrics.bounds.height() - insets.top - insets.bottom
```

**`elegantTextHeight` defaults to true**
- The `elegantTextHeight` attribute on `TextView` is now true by default for apps targeting Android 15
- Replaces the compact font metric with a taller, more readable one — increases line height for scripts with large vertical metrics
- Test all text-heavy screens, particularly on smaller Zebra displays (WS50/WS501) — rows and labels that were sized to compact font metrics may be clipped or overflow their containers

**`TextView` and `EditText` dimension changes**
- `TextView` reserves extra horizontal space for complex letter shapes (e.g., Arabic, Indic scripts) — fixed-width text containers may truncate
- `EditText` enforces a locale-aware minimum line height — single-line fields may be taller than expected
- Test all form fields and data entry screens, particularly on Zebra devices deployed in regions using non-Latin scripts

**Minimum `targetSdkVersion` 24 required to install**

Devices running Android 15 cannot install APKs with `targetSdkVersion` below 24. If you are still shipping a legacy build with a low target SDK, it cannot be sideloaded or MDM-pushed onto A15 devices.

**Pending intents canceled when package is stopped**

If a package is force-stopped (by the user via Task Manager, by the system, or by ADB), any outstanding `PendingIntent`s associated with it are now canceled. Alarm triggers and scheduled `WorkManager` jobs that fire while the app is stopped will not deliver.

- Ensure your app re-registers any critical alarms or schedules pending work in `onCreate` / on next launch rather than assuming previously registered intents will survive a force-stop

**OpenJDK 17 API behavioral changes**

Android 15 aligns with OpenJDK 17. Three specific behavioral changes affect apps targeting API 35:
- `String.format()` / `Formatter` — some edge-case format specifier behaviors changed
- `Locale.getLanguage()` — returns updated IANA language codes for certain locales (e.g., `iw` → `he`, `ji` → `yi`)
- `Random.ints()` / `Random.nextInt()` — sequence output may differ if your code assumed a specific seed behavior

If your app generates locale-sensitive strings, formats numbers/dates, or uses seeded `Random` for reproducible output, test these areas explicitly.

**WebSQL deprecated in WebView**

`WebSQL` database support is deprecated and will be removed in a future release. If any in-app `WebView` pages use `openDatabase()` (WebSQL), migrate to `IndexedDB` or `localStorage`.

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

**Foreground service notification delay (10 seconds)**
- Certain foreground services have their notification suppressed for 10 seconds after start — if the service finishes within that window, no notification is shown at all
- Affects short-lived services (progress bars, brief sync operations)
- **Impact**: Do not design UX around the foreground notification always being visible immediately — it may not appear for brief services

**Custom notification layout enforcement**
- Apps targeting API 31 that use fully custom `RemoteViews` notifications must fit within the system notification template (header area is system-controlled)
- Custom backgrounds and full-bleed layouts are no longer applied to the notification shade
- **Impact**: Test all custom notification layouts on an API 31+ device — branding or custom header designs may need to be moved into the content area

**Mic/camera quick tile toggles**
- Users can disable microphone or camera access for all apps system-wide via Quick Settings toggles
- When toggled off, camera returns a black frame and mic returns silence — no exception is thrown, no permission change fires
- **Impact**: Camera-based scanning apps may silently stop working if the user has disabled the camera toggle. There is no API to detect the toggle state — the only signal is empty/black frames
- **Zebra enterprise note**: On managed deployments, prevent users from reaching the Quick Settings panel at all. Use Zebra MX UI Manager (via StageNow or your MDM) to restrict or remove Quick Settings tiles, or use Enterprise Home Screen (EHS) to lock the status bar / notification shade so users cannot pull it down. Either approach removes the toggle from user reach without requiring any app code change

---

### Android 13 (API 33)

**Task Manager — users can stop foreground services**
- Android 13 adds a Task Manager accessible from the notification drawer that lists all apps running foreground services and lets the user stop them with one tap
- The app is force-stopped — no lifecycle callbacks fire, no `onDestroy` runs
- **Impact**: Persistent scanning or data-sync services can be killed by the user at any time. Design services to resume cleanly on next app launch. Do not store unsaved state only in memory inside a long-running service
- **Zebra enterprise note**: On dedicated-use devices, lock down the notification shade via MX UI Manager or EHS to prevent users from accessing the Task Manager — same approach as for the mic/camera Quick Settings toggles

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

**Foreground service notifications are now user-dismissible**
- Users can swipe away foreground service notifications even if the app set them as ongoing/non-dismissible — the service continues running, only the notification is gone
- **Impact**: Enterprise apps that relied on a persistent notification to communicate scanning status or connectivity state to the user can no longer guarantee that notification stays visible. Consider surfacing critical status in the app's own UI rather than relying solely on the notification
- **Zebra note**: On dedicated-use devices, this is less of a concern since users typically don't interact with the notification shade — but test your UX in case the notification disappears

**Non-linear font scaling up to 200%**
- Android 14 introduces non-linear font scaling so that large text sizes scale less aggressively than small text — at 200% scale, body text grows significantly but headings grow less
- Use `sp` units everywhere for text sizes; never `dp` for text
- **Impact on Zebra devices**: WS50/WS501 and other small-screen devices where users may increase font size to compensate for screen size — test at 130% and 200% scale, particularly data tables, scan result lists, and label fields

**Exact alarm permission revoked on upgrade**
- `SCHEDULE_EXACT_ALARM` (introduced in A12) is silently revoked when the app is updated — no system UI, no broadcast
- **Impact**: Scheduled jobs that rely on exact timing silently stop working after an OTA update. Add a `canScheduleExactAlarms()` check on `onResume` and prompt the user to re-grant if needed

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

**Non-SDK interface restrictions (all API levels, tightened each release)**

Android restricts access to non-SDK interfaces (private APIs accessed via reflection or JNI that are not part of the public SDK). The blocked list is updated in every major Android release — interfaces that worked on A11 may be blocked on A12, A13, etc.

- Run `./gradlew lint` and look for `PrivateApi` or `SoonBlockedPrivateApi` warnings
- At runtime, accessing a blocked interface throws `NoSuchMethodException`, `NoSuchFieldException`, or causes a `UnsatisfiedLinkError` (JNI)
- Android Studio's APK Analyzer and the `veridex` tool (from the Android SDK) can scan your APK for non-SDK usages before they break at runtime
- **Impact**: Third-party libraries are the most common source — update dependencies before each `targetSdk` bump and re-scan

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