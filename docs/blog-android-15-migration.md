# Your AI-Powered Guide to a Smooth Android 15 Migration

*Enterprise Android apps on Zebra devices face a set of migration challenges unique to the platform — this post walks through what changed in Android 15, what it means for your Zebra app, and how to use AI to turn it into a straightforward and positive experience.*

---

For many Android developers, the announcement of a new OS version brings a mix of excitement and a familiar sense of dread. It can feel like a monolithic, daunting task. But what if this year it could be different? What if the migration to Android 15 was not a chore, but an easy upgrade?

The truth is, the fear of the unknown is often the biggest hurdle. The migration itself is not one giant leap, but a series of small, manageable steps — and a chance to pay down technical debt and modernise your app. With the [Zebra Android Migration — AI Developer Pack](https://github.com/cbolen/Android-Migration-Guide-Pack), you get a process and an AI partner to make that happen.

Android 15 (API 35) follows Google's standard model: behaviour changes activate when your app raises its `targetSdk`. That means the migration is incremental and predictable — each API level has a well-defined set of changes, and you can address them one at a time. For Zebra developers, there are a few platform-specific considerations alongside the standard Android changes: DataWedge scanning integration, EMDK service binding, and the availability of Zebra AI Suite for advanced data capture on Android 14+ devices.

---

## What's Changing in Android 15?

### Edge-to-Edge Is Now Enforced

If you only remember one thing from this post, make it this: **apps targeting API 35 now draw behind system bars by default.** The system no longer reserves space at the top and bottom of the screen. Your content flows underneath the status bar and navigation bar — and without the right fix, bottom navigation bars, floating action buttons, and input fields will be hidden.

*[Screenshot: Inventory scan screen before edge-to-edge fix — bottom navigation bar hidden behind the gesture nav bar]*

The fix is consistent across all screens:

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

*[Screenshot: Same screen after fix — full content visible, FAB clear of nav bar]*

---

### Predictive Back Is No Longer Opt-In

The smoother, more intuitive predictive back gesture is now standard. Apps that haven't migrated from `onBackPressed()` need to complete that migration now.

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

If your destination screen has a slow `onCreate` or no background color set, users will see a blank or partial preview during the swipe — worth testing explicitly.

---

### Background Activity Launch Restrictions

There are now stricter rules about starting activities from the background. Apps can no longer launch a new screen from a `Service`, `BroadcastReceiver`, or `WorkManager` task without either a visible notification or an active user-initiated task stack. This affects workflow apps that surface an alert screen in response to a background event — a low stock warning, a sync failure, or an incoming task assignment.

The right pattern is a full-screen notification intent:

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

---

### Safer Intents

Intents are now safer by default — the intent's action, category, and data must accurately match the target component's declared `intent-filter`, and intents with no action no longer match any filter at all. For most apps this is a non-issue; DataWedge broadcast commands use the explicit `com.symbol.datawedge.api.ACTION` action and are unaffected. Where to check: any implicit intents used for internal screen routing. Convert those to explicit intents:

```kotlin
val intent = Intent(context, ScanResultActivity::class.java)
startActivity(intent)
```

---

### TLS 1.0 and 1.1 Are Blocked

Apps targeting Android 15 can no longer connect to servers using TLS 1.0 or 1.1 — those connections fail outright. Enterprise apps frequently connect to internal infrastructure — on-premise APIs, ERP systems, warehouse management servers — that may still be running older TLS configurations. Confirm all endpoints your app contacts support TLS 1.2 or higher before the migration goes out.

---

### Other Android 15 Changes to Be Aware Of

**Notification cooldown:** Android 15 automatically reduces the priority of notifications posted too rapidly from the same app. For scan-heavy warehouse or retail apps that post a new notification per barcode decode, update a single persistent notification rather than posting a new one on each scan:

```kotlin
notificationManager.notify(SCAN_NOTIFICATION_ID,
    NotificationCompat.Builder(context, CHANNEL_ID)
        .setContentTitle("Last scan: $barcode")
        .setSmallIcon(R.drawable.ic_scan)
        .setOnlyAlertOnce(true)
        .build()
)
```

**Text height changes:** The `elegantTextHeight` attribute defaults to `true` for apps targeting Android 15, increasing line height across the app. On smaller Zebra displays like the WS50 and WS501, rows and labels sized to the old compact metrics can overflow or get clipped — run a visual pass on text-heavy screens after migration.

**BOOT_COMPLETED foreground service restrictions:** `dataSync` and `mediaProcessing` foreground services can no longer start from a `BOOT_COMPLETED` receiver. Replace with `WorkManager`:

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

**Private Space:** Primarily a consumer feature — MDM solutions can disable it via policy and dedicated-use Zebra devices typically do not expose it. For most Zebra developers, no action is needed.

---

## Barcode Scanning on Zebra Devices: Use DataWedge

> **Migrating from an older targetSdk?** If your app is still targeting API 30, 31, or 33 you will also need to address the breaking changes introduced in those releases — `android:exported`, `PendingIntent` flags, `AsyncTask` removal, and more. See the [Addendum: Cumulative Changes from Android 12–14](#addendum-cumulative-changes-from-android-1214) at the end of this post for the full list with code examples.

A note that applies across all Android versions: **DataWedge is the right choice for barcode scanning on Zebra mobile computers.** Scan data arrives via broadcast intent — there is no camera or scanner API code in your app. The scanning behaviour is fully configurable through DataWedge profiles, managed by MDM without app updates.

```kotlin
class ScanReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val data = intent.getStringExtra("com.symbol.datawedge.data_string") ?: return
        val symbology = intent.getStringExtra("com.symbol.datawedge.label_type")
        // handle scan result
    }
}
```

For advanced data capture on Android 14+ devices, the Zebra AI Suite SDK complements DataWedge with AI-driven recognition via `EntityTrackerAnalyzer`. EMDK remains the right tool when your app needs direct scanner control: custom decode parameters, serial or USB-connected scanners, or payment hardware. For standard barcode scanning, DataWedge is the simpler and more maintainable path.

---

## The AI Advantage: Your Expert Programming Partner

Think of the AI assistant not as a simple tool, but as your expert partner for this journey. Loaded with Zebra-specific context, it can find where Android API changes impact your code and apply vetted patterns to fix them — consistently and without leaving your IDE.

- **It handles the tedious work:** Generates repetitive boilerplate so you can focus on what matters.
- **It ensures best practices:** Consistently applies vetted patterns, improving code quality and reducing errors.
- **It keeps you in the flow:** Instant, expert answers without hunting through documentation.

We have published an open-source AI context pack that gives any AI assistant the Zebra-specific knowledge it needs: **[cbolen/Android-Migration-Guide-Pack](https://github.com/cbolen/Android-Migration-Guide-Pack)**.

The pack includes:
- `CLAUDE.md` — auto-loaded by Claude Code when placed in your project root
- `.cursorrules` — auto-loaded by Cursor
- `docs/system-prompt.md` — paste into any AI chat tool (ChatGPT, Gemini, Claude.ai)
- `docs/migration-guide.md` — full A11-A15 reference with code examples
- `docs/datawedge-intents-ref.md` — DataWedge Intent API quick reference
- `examples/` — vetted Kotlin boilerplate for DataWedge, EMDK, permissions, storage, and edge-to-edge

### Setup in Two Minutes

**Claude Code:**
```bash
cp android-migration-guide/CLAUDE.md /path/to/your/android/project/
```

**Cursor:**
```bash
cp android-migration-guide/.cursorrules /path/to/your/android/project/
```

**GitHub Copilot:**
```bash
cp android-migration-guide/CLAUDE.md /path/to/your/android/project/.github/copilot-instructions.md
```

---

## Phase 0: Generate a Custom Plan From Your Code

This is where the fear disappears. Before you touch a single line of code, ask your AI assistant to scan your project and produce a detailed, prioritised plan. The big, scary migration becomes a simple to-do list of clearly defined tasks — showing you exactly which files need updates for edge-to-edge rendering, safer intents, and more.

Use this prompt:

```
Read CLAUDE.md and docs/migration-guide.md to load the Zebra migration context.

Then scan this entire Android project — AndroidManifest.xml, all Kotlin/Java source
files, build.gradle / build.gradle.kts, and libs.versions.toml if present.

Produce a migration plan with:
1. Blocking issues (install failure or runtime crash) — file, line, API level, fix needed
2. Required changes (silent failure or permission denied) — file, line, API level, fix needed
3. Zebra-specific issues — DataWedge receiver flags, EMDK lifecycle, storage patterns
4. Recommended tests per change area
5. Suggested order for the migration phases that apply to this project

Do not make any changes. Output the plan only.
```

*[Screenshot: Claude Code terminal output — migration plan listing issues across files, grouped by severity]*

You get a full picture of the work before a single line of code changes. Review and confirm the scope, then work through the phases. A migration that surprises you halfway through is much harder to manage than one you planned for up front.

**Want to see what this output looks like?** The [example migration plan](https://github.com/cbolen/Android-Migration-Guide-Pack/blob/master/examples/example-migration-plan.md) shows the Phase 0 output from running this prompt against the practice app. Note: that app was deliberately constructed to contain almost every possible migration issue at once — a real app will typically have a much smaller subset.

---

## Phase 1: Execute the Easy Upgrade

With your custom plan in hand, the execution is a simple, methodical loop. Follow the suggested phase order, letting your AI assistant apply the fixes identified in the plan.

*[Screenshot showing an AI assistant applying a suggested fix to a line of code.]*

The pack includes 12 focused migration prompts — one per concern — so changes stay contained and reviewable. Here are two examples:

**Manifest exported flags:**
> *Scan AndroidManifest.xml and find every `<activity>`, `<service>`, `<receiver>`, and `<provider>` that has an `<intent-filter>` but is missing `android:exported`. Add `android:exported="false"` to internal components and `android:exported="true"` only to components that must receive intents from other apps or the system. Show me the list before making changes.*

**Edge-to-edge insets:**
> *Add WindowInsetsCompat handling to all activities in this project. Apply window insets to the root view or scrollable container so content is not obscured by the status bar or navigation bar. Use ViewCompat.setOnApplyWindowInsetsListener. This is required when targeting API 35.*

For Claude Code users, the pack also includes a `migrate.sh` script that runs all 12 phases non-interactively:

```bash
git checkout -b migrate/android-15
./migrate.sh
git diff --stat
```

Each phase's changes are independently reviewable. DataWedge profile names and broadcast action strings are the one thing the AI will not know — confirm those match your DataWedge configuration after the script completes.

---

## Phase 2: Validate With Confidence

The recommended tests section of your generated plan is your primary guide here. Go through it line by line, and always do your final testing on a physical Zebra device.

| Area | What to test |
|---|---|
| Edge-to-edge | FAB and bottom nav visible in both gesture and 3-button navigation |
| Predictive back | Hardware button, gesture swipe, and predictive preview (Developer Options) |
| DataWedge scanning | Scan received correctly; receiver registered with `RECEIVER_NOT_EXPORTED` on API 33+ |
| Permissions | Fresh install (all dialogs), upgrade from old APK, "deny and don't ask again" flow |
| Storage | Create file in `getExternalFilesDir()` (no prompt), export via MediaStore, import via SAF |
| Font scale | 100%, 130%, 200% — no clipped or overlapping text |

For WS50 / WS501 wearable computers with square displays: `Configuration.orientation` returns `ORIENTATION_UNDEFINED` — make sure any orientation-gated UI handles the third case.

---

## Practice on a Known-Broken App First

If you want to validate the approach before running it on your production code, the pack references a practice app built specifically for this purpose: **[cbolen/android-migration-sample](https://github.com/cbolen/android-migration-sample)**.

It is a legacy inventory app written with API 30 patterns — `AsyncTask`, `startActivityForResult`, hardcoded storage paths, missing `exported` flags, and more. Clone it, run the migration prompts against it, and see the full process end to end before touching your real codebase.

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
- **[Example migration plan](https://github.com/cbolen/Android-Migration-Guide-Pack/blob/master/examples/example-migration-plan.md)** — Sample Phase 0 output
- [Android 15 behavior changes](https://developer.android.com/about/versions/15/behavior-changes-15)
- [DataWedge Intent API](https://techdocs.zebra.com/datawedge/latest/guide/api/)
- [Zebra AI Suite SDK](https://techdocs.zebra.com/ai-datacapture/latest/about/)
- [WindowInsetsCompat guide](https://developer.android.com/develop/ui/views/layout/edge-to-edge)
- [Zebra Developer Portal](https://developer.zebra.com)

---

*Questions or corrections? Open an issue on the GitHub repo or reach out via [developer@zebra.com](mailto:developer@zebra.com).*

*Happy coding.*

---

## Addendum: Cumulative Changes from Android 12–14

Android 15 does not arrive in isolation. Apps still targeting API 30 carry the full weight of four API level bumps. Here is what you are activating at each step — with code examples for each breaking change.

### Android 12 (API 31): Manifest, PendingIntent, and Cryptography

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

**BouncyCastle cryptographic implementations removed.** Calling `Cipher.getInstance(..., "BC")` throws `NoSuchProviderException` at runtime on API 31+. Use the default provider instead:

```kotlin
// Throws on API 31+
val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding", "BC")

// Correct — use the default provider (Conscrypt on Android)
val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
```

---

### Android 13 (API 33): Notifications, Storage, AsyncTask, DataWedge, Task Manager

**`POST_NOTIFICATIONS` is a runtime permission.** Any app that shows notifications must request it before calling `notify()`.

```kotlin
val launcher = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
    if (!granted) { /* disable notification features or show rationale */ }
}

if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
}
```

**`READ_EXTERNAL_STORAGE` is replaced by granular media permissions** — `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`.

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

**Android 13 introduces a Task Manager** accessible from the notification drawer. Users can stop any foreground service with one tap — the app is force-stopped with no lifecycle callbacks. Design for clean resumption on next launch. On dedicated-use Zebra deployments, lock down the notification shade via MX UI Manager or EHS.

---

### Android 14 (API 34): Foreground Services, Notifications, and AI Suite

**Foreground service types are strictly enforced.** A foreground service without a declared type crashes at runtime:

```xml
<service
    android:name=".SyncService"
    android:foregroundServiceType="dataSync"
    android:exported="false" />
```

**`USE_FULL_SCREEN_INTENT` is restricted to alarm and calling apps.** For enterprise alert scenarios, replace full-screen intents with high-priority `IMPORTANCE_HIGH` notification channels:

```kotlin
val nm = getSystemService(NotificationManager::class.java)
if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE || nm.canUseFullScreenIntent()) {
    // attach full-screen intent as before
} else {
    // use IMPORTANCE_HIGH channel for heads-up notification instead
}
```

**Zebra AI Suite becomes available at API 34.** AI-based barcode recognition, OCR, and shelf analysis via `EntityTrackerAnalyzer` are available for apps targeting Android 14+. See the [Zebra AI Suite SDK docs](https://techdocs.zebra.com/ai-datacapture/latest/about/) for integration details.
