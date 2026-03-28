# Migrating Your Zebra App to Android 15: A Practical Guide (With AI)

*Enterprise Android apps on Zebra devices face a set of migration challenges unique to the platform — this post walks through what changed in Android 15, what it means for your Zebra app, and how to automate the bulk of the migration using AI coding tools.*

---

## What to Expect From the Android 15 Migration

Android 15 (API 35) follows Google's standard model: behavior changes activate when your app raises its `targetSdk`. That means the migration is incremental and predictable — each API level has a well-defined set of changes, and you can address them one at a time.

For Zebra developers, there are a few platform-specific considerations alongside the standard Android changes: DataWedge scanning integration, EMDK service binding, and the availability of Zebra AI Suite for advanced data capture on Android 14+ devices.

The full migration is well-documented, and AI coding assistants can automate the majority of the mechanical changes — if they have the right Zebra context loaded.

---

## What Changed in Android 15

### The Biggest Change: Edge-to-Edge Is Now Enforced

If you only remember one thing from this post, make it this: **apps targeting API 35 now draw behind system bars by default.** The system no longer reserves space at the top and bottom of the screen for the status bar and navigation bar. Your content will flow underneath them.

*[Screenshot: Inventory scan screen before edge-to-edge fix — bottom navigation bar hidden behind the gesture nav bar]*

The fix is consistent across all screens. In a View-based app, apply insets in `Activity.onCreate` after `setContentView`:

```kotlin
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

*[Screenshot: Same inventory scan screen after edge-to-edge fix — full content visible, FAB clear of nav bar]*

This is the single highest-impact visual regression on Android 15. Bottom navigation bars, floating action buttons, and input fields are the elements most commonly hidden.

---

### Predictive Back Is No Longer Opt-In

Predictive back gesture — the animation that previews the destination screen as you swipe from the edge — is now enforced for all apps on Android 15. Apps that haven't migrated from `onBackPressed()` need to complete that migration now.

```kotlin
// Remove this
override fun onBackPressed() {
    if (hasUnsavedChanges) confirmDiscard() else super.onBackPressed()
}

// Replace with this
onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
    override fun handleOnBackPressed() {
        if (hasUnsavedChanges) confirmDiscard() else {
            isEnabled = false
            onBackPressedDispatcher.onBackPressed()
        }
    }
})
```

*[Screenshot: Predictive back preview mid-swipe on an inventory detail screen]*

If your destination screen has a slow `onCreate` or no background color set, users will see a blank or partial preview during the swipe — before completing the gesture. This is a UX issue worth testing explicitly.

---

### Notification Cooldown

Android 15 automatically reduces the priority of notifications posted too rapidly from the same app. There's no API change required, but it's a behavioral shift worth knowing about for scan-heavy warehouse or retail apps.

If your app posts a new notification for every barcode decode — common in pick-and-pack or receiving workflows — those notifications can be silently downgraded during a fast scanning session. The fix is straightforward: update a single persistent notification rather than posting a new one per scan.

```kotlin
// Instead of notify() on every scan, update the same notification ID
notificationManager.notify(SCAN_NOTIFICATION_ID,
    NotificationCompat.Builder(context, CHANNEL_ID)
        .setContentTitle("Last scan: $barcode")
        .setSmallIcon(R.drawable.ic_scan)
        .setOnlyAlertOnce(true) // no sound/vibration on updates
        .build()
)
```

---

### Background Activity Launch Restrictions

Android 15 tightens the rules around launching activities from the background. Apps can no longer start a new screen from a `Service`, `BroadcastReceiver`, or `WorkManager` task without either a visible notification or an active user-initiated task stack.

This affects workflow apps that surface an alert screen in response to a background event — a low stock warning, a sync failure, or an incoming task assignment.

The right pattern for these cases is a full-screen notification intent:

```kotlin
val fullScreenIntent = PendingIntent.getActivity(
    context, 0, Intent(context, AlertActivity::class.java), PendingIntent.FLAG_IMMUTABLE
)
val notification = NotificationCompat.Builder(context, CHANNEL_ID)
    .setContentTitle("Action required")
    .setContentText("Incoming pick task assigned")
    .setSmallIcon(R.drawable.ic_alert)
    .setFullScreenIntent(fullScreenIntent, true)
    .build()

notificationManager.notify(ALERT_NOTIFICATION_ID, notification)
```

The system shows the notification and, on lock screen or when the app is in the foreground, launches the activity directly.

---

### Private Space — A Note for Enterprise Deployments

Android 15 introduces Private Space: a secondary locked profile on the device where users can install sensitive personal apps, hidden behind a separate PIN. It's primarily a consumer feature.

For enterprise Zebra deployments, Private Space is unlikely to be a factor — MDM solutions can disable it via policy, and dedicated-use devices (warehouse, retail, healthcare) typically don't expose it to end users at all.

If your app could end up installed into Private Space (less common in enterprise contexts): apps in Private Space run as an isolated user profile with their own app data and storage. DataWedge profile association uses the app's package name, which remains the same — but the profile runs independently from the main profile, so DataWedge must be configured for that context.

For most Zebra developers, no action is needed. If your MDM policy doesn't already restrict Private Space, it's worth confirming with your EMM provider.

---

### Safer Intents

Android 15 enforces stricter matching rules for intents targeting specific components: the intent's action, category, and data must accurately match the target component's declared `intent-filter`. Intents with no action no longer match any filter at all.

For most apps this is a non-issue — DataWedge broadcast commands use the explicit `com.symbol.datawedge.api.ACTION` action and are unaffected. Where to check: any implicit intents used for internal screen routing. Convert those to explicit intents:

```kotlin
// Replace implicit internal intents with explicit ones
val intent = Intent(context, ScanResultActivity::class.java)
startActivity(intent)
```

---

### TLS 1.0 and 1.1 Are Blocked

Apps targeting Android 15 can no longer connect to servers using TLS 1.0 or 1.1 — those connections fail outright. For consumer apps this is rarely an issue, but enterprise apps frequently connect to internal infrastructure — on-premise APIs, ERP systems, warehouse management servers — that may still be running older TLS configurations.

Check all endpoints your app contacts and confirm they support TLS 1.2 or higher. If any don't, this is a conversation to have with your IT or infrastructure team before the migration goes out.

---

### BOOT_COMPLETED Foreground Service Restrictions

If your app auto-starts a service when the device boots — common in scan-and-sync or always-on workflow apps — Android 15 restricts which foreground service types can be launched from a `BOOT_COMPLETED` receiver. Types like `dataSync` and `mediaProcessing` are affected.

The recommended replacement is `WorkManager` with a boot trigger, which handles the scheduling and lifecycle correctly:

```kotlin
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            WorkManager.getInstance(context).enqueue(
                OneTimeWorkRequestBuilder<SyncWorker>().build()
            )
        }
    }
}
```

---

### Text Height Changes — Watch Small Screens

The `elegantTextHeight` attribute on `TextView` now defaults to `true` for apps targeting Android 15. It switches from a compact font metric to a taller, more readable one designed for scripts with large vertical metrics (Arabic, Thai, and others).

In practice this increases line height across the app. For most screens it's barely noticeable — but on smaller Zebra displays like the WS50 and WS501, rows and labels sized to the old compact metrics can overflow their containers or get clipped. Run a visual pass on text-heavy screens and scan result lists after migration.

---

## The Cumulative Changes from Android 12–14

Android 15 doesn't arrive in isolation. Apps still targeting API 30 carry the full weight of four API level bumps. Here's what you're activating at each step.

### Android 12 (API 31): Manifest and PendingIntent

**Every manifest component with an `<intent-filter>` must declare `android:exported`** — your app will fail to install without it.

```xml
<!-- Before — install fails on API 31+ -->
<activity android:name=".ScanResultActivity">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
    </intent-filter>
</activity>

<!-- After -->
<activity android:name=".ScanResultActivity" android:exported="false">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
    </intent-filter>
</activity>
```

**All `PendingIntent` calls must declare a mutability flag** — without it, an exception is thrown at runtime.

```kotlin
// Before — throws on API 31+
val pending = PendingIntent.getActivity(context, 0, intent, 0)

// After
val pending = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)
```

---

### Android 13 (API 33): Notifications, Storage, AsyncTask, DataWedge

**`POST_NOTIFICATIONS` is a runtime permission.** Any app that shows notifications must request it at an appropriate moment before calling `notify()`.

```kotlin
val launcher = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
    if (!granted) { /* disable notification features or show rationale */ }
}

if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
}
```

**`READ_EXTERNAL_STORAGE` is replaced by granular media permissions** — `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`. Use `maxSdkVersion` to scope permissions correctly across API levels.

**`AsyncTask` is removed.** Replace with coroutines:

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

**DataWedge scan receivers need a new export flag on API 33+.** DataWedge broadcasts come from a system service — use `RECEIVER_NOT_EXPORTED`:

```kotlin
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    registerReceiver(scanReceiver, IntentFilter(SCAN_ACTION), RECEIVER_NOT_EXPORTED)
} else {
    registerReceiver(scanReceiver, IntentFilter(SCAN_ACTION))
}
```

---

### Android 14 (API 34): Foreground Services and AI Suite

**Foreground service types are strictly enforced.** A foreground service without a declared type crashes at runtime. Add `foregroundServiceType` to the manifest:

```xml
<service
    android:name=".SyncService"
    android:foregroundServiceType="dataSync"
    android:exported="false" />
```

Valid types include `dataSync`, `location`, `mediaPlayback`, `camera`, `connectedDevice`, and others — choose the type that accurately describes what the service is doing.

**Zebra AI Suite becomes available at API 34.** If you're building apps that need AI-based barcode recognition, OCR, or shelf analysis on Zebra devices, Android 14 is the minimum API level required to use it. See the [Zebra AI Suite SDK docs](https://techdocs.zebra.com/ai-datacapture/latest/about/) for integration details.

---

## Barcode Scanning on Zebra Devices: Use DataWedge

A note that applies across all Android versions: **DataWedge is the right choice for barcode scanning on Zebra mobile computers.** Scan data arrives via broadcast intent — there is no camera or scanner API code in your app. The scanning behavior is fully configurable through DataWedge profiles, managed by MDM without app updates.

```kotlin
class ScanReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val data = intent.getStringExtra("com.symbol.datawedge.data_string") ?: return
        val symbology = intent.getStringExtra("com.symbol.datawedge.label_type")
        // handle scan result
    }
}
```

For advanced data capture scenarios on Android 14+ devices — AI-based barcode recognition, OCR, or shelf analysis — the Zebra AI Suite SDK complements DataWedge with AI-driven recognition via `EntityTrackerAnalyzer`.

EMDK remains the right tool when your app needs direct scanner control: custom decode parameters, serial or USB-connected scanners, or payment hardware. For standard barcode scanning, DataWedge is the simpler and more maintainable path.

---

## Using AI to Automate the Migration

The migration changes above are mechanical and repetitive. They follow consistent, predictable patterns — exactly the kind of work AI coding assistants handle well. The challenge is that most AI tools don't know about DataWedge, EMDK, or the behavior differences between Zebra device families out of the box.

We've published an open-source AI context pack that solves this: **[cbolen/Android-Migration-Guide-Pack](https://github.com/cbolen/Android-Migration-Guide-Pack)**.

*[Screenshot: GitHub repo — Android-Migration-Guide-Pack showing CLAUDE.md, .cursorrules, docs/, and examples/ folders]*

The pack includes:
- `CLAUDE.md` — auto-loaded by Claude Code when placed in your project root
- `.cursorrules` — auto-loaded by Cursor
- `docs/system-prompt.md` — paste into any AI chat tool (ChatGPT, Gemini, Claude.ai)
- `docs/migration-guide.md` — full A11–A15 reference
- `docs/datawedge-intents-ref.md` — DataWedge Intent API quick reference
- `examples/` — vetted Kotlin boilerplate for DataWedge, EMDK, permissions, storage, and edge-to-edge

### Setup in Two Minutes

**Claude Code:**
```bash
cp android-migration-guide/CLAUDE.md /path/to/your/android/project/
```
Claude Code reads `CLAUDE.md` automatically at session start. No other setup required.

**Cursor:**
```bash
cp android-migration-guide/.cursorrules /path/to/your/android/project/
```

**GitHub Copilot:**
```bash
cp android-migration-guide/CLAUDE.md /path/to/your/android/project/.github/copilot-instructions.md
```

---

### Running the Migration Phase by Phase

The pack includes 12 focused migration prompts — one per concern — so changes stay contained and reviewable. Here's what a few of them look like in practice.

**Phase 1 — Manifest exported flags:**
> *Scan AndroidManifest.xml and find every `<activity>`, `<service>`, `<receiver>`, and `<provider>` that has an `<intent-filter>` but is missing `android:exported`. Add `android:exported="false"` to internal components and `android:exported="true"` only to components that must receive intents from other apps or the system. Show me the list before making changes.*

*[Screenshot: Claude Code terminal output showing list of manifest components identified before making changes]*

**Phase 9 — Edge-to-edge insets:**
> *Add WindowInsetsCompat handling to all activities in this project. Apply window insets to the root view or scrollable container so content is not obscured by the status bar or navigation bar. Use ViewCompat.setOnApplyWindowInsetsListener. This is required when targeting API 35.*

*[Screenshot: Claude Code making targeted edits to multiple activity files in sequence]*

---

### Fully Automated: migrate.sh

For Claude Code users, the pack includes a `migrate.sh` script that runs all 12 phases non-interactively using the `-p` flag:

```bash
#!/bin/bash
set -e

echo "=== Phase 1: android:exported ==="
claude -p "Scan AndroidManifest.xml and add android:exported to every activity, service, \
receiver, and provider that has an intent-filter but is missing the attribute. \
Use false for internal components, true only for components that must accept external intents." \
--allowedTools Edit,Read,Glob,Grep

echo "=== Phase 2: PendingIntent FLAG_IMMUTABLE ==="
claude -p "Find all PendingIntent.getActivity, getBroadcast, and getService calls missing \
FLAG_IMMUTABLE and add it. Only use FLAG_MUTABLE where genuinely required." \
--allowedTools Edit,Read,Glob,Grep

# ... phases 3–11 ...

echo "=== Phase 12: Build target ==="
claude -p "Update build.gradle to compileSdk 35, targetSdk 35, minSdk 30. \
Add any Jetpack dependencies required by the changes made in previous phases." \
--allowedTools Edit,Read,Glob,Grep
```

Run it on a clean branch so each phase is independently reviewable:

```bash
git checkout -b migrate/android-15
./migrate.sh
git diff --stat
```

*[Screenshot: Terminal output of migrate.sh running — each phase echoed, Claude making edits, final git diff --stat showing files changed]*

After the script completes, review changes with `git diff` before committing. DataWedge profile names and broadcast action strings are the one thing the AI won't know — confirm those match your DataWedge configuration.

---

### Practice on a Known-Broken App First

If you want to validate the approach before running it on production code, the pack references a practice app built specifically for this purpose: **[cbolen/android-migration-sample](https://github.com/cbolen/android-migration-sample)**.

It's a legacy inventory app written with API 30 patterns — `AsyncTask`, `startActivityForResult`, hardcoded storage paths, missing `exported` flags, the works. Clone it, run the migration prompts against it, and see the full process end to end before touching your real codebase.

*[Screenshot: android-migration-sample open in Android Studio — showing legacy patterns in MainActivity.kt and ScanActivity.kt]*

---

## Testing After Migration

The places most likely to surface regressions:

| Area | What to test |
|---|---|
| Edge-to-edge | FAB and bottom nav visible in both gesture and 3-button navigation |
| Predictive back | Hardware button, gesture swipe, and predictive preview (Developer Options) |
| DataWedge scanning | Scan received correctly, receiver registered with `RECEIVER_NOT_EXPORTED` on API 33+ |
| Permissions | Fresh install (all dialogs), upgrade from old APK, "deny and don't ask again" flow |
| Storage | Create file in `getExternalFilesDir()` (no prompt), export via MediaStore, import via SAF |
| Font scale | 100%, 130%, 200% — no clipped or overlapping text |

For WS50 / WS501 wearable computers with square displays: `Configuration.orientation` returns `ORIENTATION_UNDEFINED` on those devices — make sure any orientation-gated UI handles the third case, and test the emulator AVD described in the migration guide appendix.

---

## Release Checklist

Before publishing to the Play Store or deploying via MDM:

- [ ] `compileSdk 35`, `targetSdk 35`
- [ ] All `android:exported` attributes set on components with `<intent-filter>`
- [ ] All `PendingIntent` calls have `FLAG_IMMUTABLE` or `FLAG_MUTABLE`
- [ ] `POST_NOTIFICATIONS` requested before any `notify()` call
- [ ] No `READ_EXTERNAL_STORAGE` without `maxSdkVersion="32"` guard
- [ ] No `onBackPressed()` overrides
- [ ] No `startActivityForResult` / `onActivityResult`
- [ ] No `AsyncTask`
- [ ] Foreground service types declared in manifest
- [ ] Edge-to-edge insets handled in all screens
- [ ] DataWedge receivers use `RECEIVER_NOT_EXPORTED` on API 33+
- [ ] Lint passes with no `Error` severity issues

---

## Resources

- **[Android-Migration-Guide-Pack](https://github.com/cbolen/Android-Migration-Guide-Pack)** — AI context files, migration reference, and code examples
- **[android-migration-sample](https://github.com/cbolen/android-migration-sample)** — Practice app with deliberate legacy patterns
- [Android 15 behavior changes](https://developer.android.com/about/versions/15/behavior-changes-15)
- [DataWedge Intent API](https://techdocs.zebra.com/datawedge/latest/guide/api/)
- [Zebra AI Suite SDK](https://techdocs.zebra.com/ai-datacapture/latest/about/)
- [WindowInsetsCompat guide](https://developer.android.com/develop/ui/views/layout/edge-to-edge)
- [Zebra Developer Portal](https://developer.zebra.com)

---

*Questions or corrections? Open an issue on the GitHub repo or reach out via [developer@zebra.com](mailto:developer@zebra.com).*
