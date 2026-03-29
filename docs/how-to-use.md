# How to Use the AI Migration Pack With Your Own Project

This guide shows how to add the migration context files to your existing Android project so any AI coding assistant can help automate the migration to Android 15.

---

## Step 1 — Get the Files

Clone or download the pack from GitHub:

```bash
git clone https://github.com/zebra-oss/android-migration-guide.git
```

Or download the ZIP from the Releases page and unzip it.

---

## Step 2 — Add the Right File for Your AI Tool

Each AI tool looks for context in a different place. Copy one file — you do not need all of them.

| AI Tool | File to copy | Where to put it in your project |
|---|---|---|
| **Claude Code** (CLI) | `CLAUDE.md` | Your Android project root |
| **Cursor** | `.cursorrules` | Your Android project root |
| **GitHub Copilot** | `CLAUDE.md` content | `.github/copilot-instructions.md` |
| **Claude.ai, ChatGPT, Gemini** | `docs/system-prompt.md` | Paste as your first message |

### Claude Code

```bash
cp android-migration-guide/CLAUDE.md /path/to/your/android/project/CLAUDE.md
```

Claude Code reads `CLAUDE.md` automatically when you start a session in that directory. No other setup required.

### Cursor

```bash
cp android-migration-guide/.cursorrules /path/to/your/android/project/.cursorrules
```

Cursor reads `.cursorrules` automatically when you open the project.

### GitHub Copilot (VS Code or JetBrains)

```bash
mkdir -p /path/to/your/android/project/.github
cp android-migration-guide/CLAUDE.md /path/to/your/android/project/.github/copilot-instructions.md
```

Copilot reads `.github/copilot-instructions.md` automatically across the workspace.

### Optional — Add the full reference docs

If you want the AI to have the detailed migration guide and DataWedge reference available without pasting them manually:

```bash
mkdir -p /path/to/your/android/project/docs/migration
cp android-migration-guide/docs/migration-guide.md /path/to/your/android/project/docs/migration/
cp android-migration-guide/docs/datawedge-intents-ref.md /path/to/your/android/project/docs/migration/
```

Claude Code and Cursor will index these files and reference them when relevant.

---

## Step 3 — Run the Migration Prompts

Work through the phases below in order. Start with Phase 0 to get a full picture of what needs to change before touching any code.

### Phase 0 — Discovery: Full Project Audit and Migration Plan

Run this first. It makes no changes — it reads your project and produces a prioritised list of everything that needs to be done, so you know the full scope before starting.

```
Read CLAUDE.md and docs/migration-guide.md to load the Zebra migration context.

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
   - Recommend which of the migration phases (1–12) apply to this project and in what order

Do not make any changes. Output the plan only.
```

Review the output and confirm the scope before running any subsequent phase.

---

### Phase 1 — Manifest: android:exported

```
Scan AndroidManifest.xml and find every <activity>, <service>, <receiver>, and <provider>
that has an <intent-filter> but is missing android:exported.
Add android:exported="false" to internal components and android:exported="true" only
to components that must receive intents from other apps or the system (e.g. launcher
activities, share targets, system broadcast receivers). Show me the list before making changes.
```

### Phase 2 — PendingIntent flags

```
Find all PendingIntent.getActivity(), PendingIntent.getBroadcast(), and
PendingIntent.getService() calls in this project. Add FLAG_IMMUTABLE to every one that
doesn't already have it. Only use FLAG_MUTABLE if the PendingIntent is used with
AlarmManager.setExact() or a notification with inline reply — explain any MUTABLE cases
before changing them.
```

### Phase 3 — Activity Results

```
Replace all startActivityForResult() and onActivityResult() patterns in this project
with the registerForActivityResult() API using ActivityResultContracts.
Migrate camera capture, gallery picker, and any other result flows.
Keep the same business logic — only change the API pattern.
```

### Phase 4 — Permission Results

```
Replace all onRequestPermissionsResult() overrides with registerForActivityResult()
using ActivityResultContracts.RequestPermission or RequestMultiplePermissions.
Update the permission request call sites to match.
```

### Phase 5 — Storage paths

```
Find every place this project writes or reads files using hardcoded paths
(/sdcard/, /storage/emulated/0/, Environment.getExternalStorageDirectory())
or Environment.getExternalStoragePublicDirectory().
Migrate app-private files to getExternalFilesDir().
Migrate files that should be visible in Downloads or shared media to MediaStore.
Do not use MANAGE_EXTERNAL_STORAGE.
```

### Phase 6 — AsyncTask

```
Replace all AsyncTask subclasses in this project with Kotlin coroutines.
Use viewModelScope or lifecycleScope as appropriate.
Move background work to Dispatchers.IO and UI updates to Dispatchers.Main.
Keep the same data flow and error handling logic.
```

### Phase 7 — POST_NOTIFICATIONS permission

```
Find all places this project shows notifications via NotificationManager.notify().
Add a POST_NOTIFICATIONS runtime permission check before every notify() call
(required on API 33+). Use ActivityResultContracts.RequestPermission to request it.
Also check that PendingIntent flags are FLAG_IMMUTABLE on all notification actions.
```

### Phase 8 — Back navigation

```
Replace all override fun onBackPressed() implementations with OnBackPressedCallback
registered via onBackPressedDispatcher.addCallback().
Preserve the existing back navigation logic inside the callback's handleOnBackPressed().
```

### Phase 9 — Edge-to-edge insets

```
Add WindowInsetsCompat handling to all activities in this project.
Apply window insets to the root view or scrollable container so content is not
obscured by the status bar or navigation bar. Use ViewCompat.setOnApplyWindowInsetsListener.
This is required when targeting API 35.
```

### Phase 10 — Splash screen

```
Remove the custom SplashActivity and replace it with the androidx.core:core-splashscreen
library. Add the dependency to build.gradle, add the Theme.SplashScreen parent to the
app theme in styles.xml, and call installSplashScreen() in MainActivity.onCreate()
before setContentView.
```

### Phase 11 — DataWedge receiver registration (API 33+)

```
Find all dynamic registerReceiver() calls for DataWedge scan receivers in this project.
Update them to pass RECEIVER_NOT_EXPORTED as the export flag when running on API 33+,
using a Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU check.
DataWedge broadcasts come from a system service and do not require RECEIVER_EXPORTED.
```

### Phase 12 — Build target

```
Update app/build.gradle (or build.gradle.kts):
- compileSdk 35
- targetSdk 35
- minSdk 30 (or confirm with me if a lower minimum is required)
Add any missing Jetpack dependencies needed for the changes made in earlier phases
(activity-ktx, core-splashscreen, etc.).
```

---

## Claude Code — Automated Script

If you are using Claude Code, you can run the full migration non-interactively using the `-p` flag. This runs each phase as a separate command so changes are focused and reviewable.

Create `migrate.sh` in your project root:

```bash
#!/bin/bash
set -e

# ============================================================
# PRE-FLIGHT: Run the Phase 0 discovery prompt BEFORE this
# script. It produces a migration plan with no code changes
# so you know the full scope before automation begins.
#
# Run it manually in Claude Code:
#
#   Read CLAUDE.md and docs/migration-guide.md to load the
#   Zebra migration context. Then scan this entire Android
#   project — AndroidManifest.xml, all Kotlin/Java source
#   files, build.gradle / build.gradle.kts, and
#   libs.versions.toml if present. Produce a prioritised
#   migration plan: (1) blocking issues that cause crashes or
#   install failures, (2) required behavioural changes,
#   (3) Zebra-specific issues, (4) recommended tests per
#   change area. Do not make any changes — output the plan
#   only.
#
# Review and confirm the plan, then run this script.
# ============================================================

echo "=== Phase 1: android:exported ==="
claude -p "Scan AndroidManifest.xml and add android:exported to every activity, service, receiver, and provider that has an intent-filter but is missing the attribute. Use false for internal components, true only for components that must accept external intents." --allowedTools Edit,Read,Glob,Grep

echo "=== Phase 2: PendingIntent FLAG_IMMUTABLE ==="
claude -p "Find all PendingIntent.getActivity, getBroadcast, and getService calls missing FLAG_IMMUTABLE and add it. Only use FLAG_MUTABLE where genuinely required." --allowedTools Edit,Read,Glob,Grep

echo "=== Phase 3: Activity Results ==="
claude -p "Replace all startActivityForResult and onActivityResult usage with registerForActivityResult using ActivityResultContracts. Keep existing business logic." --allowedTools Edit,Read,Glob,Grep

echo "=== Phase 4: Permission Results ==="
claude -p "Replace all onRequestPermissionsResult overrides with registerForActivityResult using ActivityResultContracts.RequestPermission or RequestMultiplePermissions." --allowedTools Edit,Read,Glob,Grep

echo "=== Phase 5: Storage paths ==="
claude -p "Find and replace hardcoded external storage paths and Environment.getExternalStorageDirectory() usage. Migrate to getExternalFilesDir() for app-private files and MediaStore for shared media." --allowedTools Edit,Read,Glob,Grep

echo "=== Phase 6: AsyncTask ==="
claude -p "Replace all AsyncTask subclasses with Kotlin coroutines using viewModelScope or lifecycleScope. Move IO work to Dispatchers.IO." --allowedTools Edit,Read,Glob,Grep

echo "=== Phase 7: POST_NOTIFICATIONS ==="
claude -p "Add POST_NOTIFICATIONS permission check before all NotificationManager.notify() calls. Add the permission to AndroidManifest.xml." --allowedTools Edit,Read,Glob,Grep

echo "=== Phase 8: Back navigation ==="
claude -p "Replace all onBackPressed() overrides with OnBackPressedCallback registered via onBackPressedDispatcher.addCallback()." --allowedTools Edit,Read,Glob,Grep

echo "=== Phase 9: Edge-to-edge insets ==="
claude -p "Add WindowInsetsCompat inset handling to all activities so content is not obscured by system bars. Required for targetSdk 35." --allowedTools Edit,Read,Glob,Grep

echo "=== Phase 10: Splash screen ==="
claude -p "Remove custom SplashActivity and replace with androidx.core:core-splashscreen. Add the dependency, update the theme, and call installSplashScreen() in MainActivity." --allowedTools Edit,Read,Glob,Grep

echo "=== Phase 11: DataWedge receiver flag ==="
claude -p "Update all registerReceiver calls for DataWedge scan receivers to pass RECEIVER_NOT_EXPORTED on API 33+ with a Build.VERSION.SDK_INT check." --allowedTools Edit,Read,Glob,Grep

echo "=== Phase 12: Build target ==="
claude -p "Update build.gradle to compileSdk 35, targetSdk 35, minSdk 30. Add any Jetpack dependencies required by the changes made in previous phases." --allowedTools Edit,Read,Glob,Grep

echo "=== Migration complete — review changes with: git diff ==="
```

Run it:

```bash
chmod +x migrate.sh
./migrate.sh
```

Review all changes before committing:

```bash
git diff
git diff --stat
```

> **Important**: Run the script in a clean git branch so you can review and revert individual phases if needed.
> ```bash
> git checkout -b migrate/android-15
> ./migrate.sh
> ```

---

## Tips for Better Results

**Work in one file at a time for large files.** If a file has multiple issues, scope the prompt:
```
In MainActivity.kt, replace startActivityForResult with registerForActivityResult.
Do not change anything else in this file.
```

**Ask for a plan before changes on complex phases.** For AsyncTask migrations:
```
List all AsyncTask subclasses in this project and describe what each one does.
Then propose which coroutine scope (viewModelScope, lifecycleScope, or a plain
coroutineScope) is appropriate for each, and why. Do not make changes yet.
```

**Verify DataWedge changes carefully.** The scan receiver registration and broadcast action string must match your DataWedge profile configuration. The AI will not know your profile name — confirm these values after migration.

**Check WS50 / WS501 square display behavior separately.** After migration, test `Configuration.orientation` — it returns `ORIENTATION_UNDEFINED` on square displays. See the migration guide appendix for handling guidance.