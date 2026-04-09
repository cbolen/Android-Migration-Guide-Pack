# Zebra Android Migration — AI Developer Pack

Context files and migration prompts to help developers port Android apps to Android 11–15 using AI coding assistants (Claude Code, Cursor, GitHub Copilot, ChatGPT, Gemini).

> **Caution:** This pack uses AI to assist with migration analysis and code changes. AI suggestions can contain errors, miss edge cases, or produce code that compiles but behaves incorrectly. Always review every change before committing, test on real devices at each API level, and consult the official [Android API documentation](https://developer.android.com/about/versions) and [Zebra TechDocs](https://techdocs.zebra.com) when in doubt. This pack is a productivity aid, not a substitute for developer judgment.

## What's Included

| File | Purpose |
|---|---|
| `CLAUDE.md` | Drop in project root — Claude Code loads it automatically |
| `.cursorrules` | Drop in project root — Cursor loads it automatically |
| `docs/migration-guide.md` | Full A11–A15 migration reference with Kotlin examples |
| `docs/toolchain-upgrade.md` | Prerequisite: JDK → Gradle → AGP upgrade guide |
| `docs/datawedge-intents-ref.md` | DataWedge Intent API quick reference |
| `docs/system-prompt.md` | Context file to paste into AI chat tools (ChatGPT, Gemini, Claude.ai) |
| `examples/` | Vetted Kotlin boilerplate for common Zebra patterns |
| `examples/example-migration-plan.md` | Sample Phase 0 output — shows what AI analysis looks like |

---

## Step 1 — Get the Files

```bash
git clone https://github.com/cbolen/android-migration-guide-pack.git
```

Or download the ZIP from the Releases page.

---

## Step 2 — Add Context to Your AI Tool

### IDE tools with project file access (Claude Code, Cursor, GitHub Copilot)

Copy the context file into your Android project root — the AI picks it up automatically.

| Tool | File to copy | Where |
|---|---|---|
| Claude Code | `CLAUDE.md` | Your Android project root |
| Cursor | `.cursorrules` | Your Android project root |
| GitHub Copilot | `CLAUDE.md` content | `.github/copilot-instructions.md` |

```bash
# Claude Code
cp android-migration-guide-pack/CLAUDE.md /path/to/your/project/

# Cursor
cp android-migration-guide-pack/.cursorrules /path/to/your/project/

# GitHub Copilot
mkdir -p /path/to/your/project/.github
cp android-migration-guide-pack/CLAUDE.md /path/to/your/project/.github/copilot-instructions.md
```

Also copy the reference docs so the AI can read them directly from your project:

```bash
mkdir -p /path/to/your/project/docs/migration
cp android-migration-guide-pack/docs/migration-guide.md /path/to/your/project/docs/migration/
cp android-migration-guide-pack/docs/datawedge-intents-ref.md /path/to/your/project/docs/migration/
```

### AI chat tools (ChatGPT, Gemini, Claude.ai)

Open `docs/system-prompt.md` and paste the full contents as your first message, then paste your `AndroidManifest.xml`, `build.gradle`, and any source files you want help with.

---

## Step 3 — Run the Migration Prompts

Work through the phases below in order. **Start with Phase 0** — it makes no code changes and produces a prioritized list of everything that needs fixing so you know the full scope before starting.

> **Prerequisite:** If your project is on AGP 4.x or 7.x, complete the toolchain upgrade first (`docs/toolchain-upgrade.md`) before running any targetSdk migration phases.

### Phase 0 — Discovery: Full Project Audit

Run this first. No changes — audit only.

```
Read CLAUDE.md for Zebra platform rules and docs/migration/migration-guide.md for the
full A11–A15 change reference.

Scan this entire Android project — AndroidManifest.xml, all Kotlin/Java source files,
build.gradle / build.gradle.kts, and libs.versions.toml if present.

Produce a migration plan with the following sections:
1. BLOCKING ISSUES (install failure or runtime crash) — file, line, API level, fix needed
2. REQUIRED CHANGES (silent failure or permission denied) — file, line, API level, fix needed
3. ZEBRA-SPECIFIC ISSUES — DataWedge receiver flags, EMDK lifecycle, storage patterns
4. SUGGESTED PHASE ORDER — which phases apply to this project and in what order

Do not make any changes. Output the plan only.
```

> **Chat tools:** Replace the first paragraph with: "I have pasted the Zebra migration context and my project files above."

Review the output and confirm scope before proceeding.

---

### Phase 1 — Manifest: android:exported

```
Refer to docs/migration/migration-guide.md for Kotlin examples and detailed guidance on this change.

Scan AndroidManifest.xml and find every <activity>, <service>, <receiver>, and <provider>
that has an <intent-filter> but is missing android:exported.
Add android:exported="false" to internal components and android:exported="true" only
to components that must receive intents from other apps or the system (e.g. launcher
activities, share targets, system broadcast receivers). Show me the list before making changes.
```

### Phase 2 — PendingIntent flags

```
Refer to docs/migration/migration-guide.md for Kotlin examples and detailed guidance on this change.

Find all PendingIntent.getActivity(), PendingIntent.getBroadcast(), and
PendingIntent.getService() calls in this project. Add FLAG_IMMUTABLE to every one that
doesn't already have it. Only use FLAG_MUTABLE if the PendingIntent is used with
AlarmManager.setExact() or a notification with inline reply — explain any MUTABLE cases
before changing them.
```

### Phase 3 — Activity Results

```
Refer to docs/migration/migration-guide.md for Kotlin examples and detailed guidance on this change.

Replace all startActivityForResult() and onActivityResult() patterns in this project
with the registerForActivityResult() API using ActivityResultContracts.
Keep the same business logic — only change the API pattern.
```

### Phase 4 — Permission Results

```
Refer to docs/migration/migration-guide.md for Kotlin examples and detailed guidance on this change.

Replace all onRequestPermissionsResult() overrides with registerForActivityResult()
using ActivityResultContracts.RequestPermission or RequestMultiplePermissions.
Update the permission request call sites to match.
```

### Phase 5 — Storage paths

```
Refer to docs/migration/migration-guide.md for Kotlin examples and detailed guidance on this change.

Find every place this project writes or reads files using hardcoded paths
(/sdcard/, /storage/emulated/0/, Environment.getExternalStorageDirectory()).
Migrate app-private files to getExternalFilesDir().
Migrate files that should be visible in Downloads or shared media to MediaStore.
Do not use MANAGE_EXTERNAL_STORAGE.
```

### Phase 6 — AsyncTask

```
Refer to docs/migration/migration-guide.md for Kotlin examples and detailed guidance on this change.

Replace all AsyncTask subclasses in this project with Kotlin coroutines.
Use viewModelScope or lifecycleScope as appropriate.
Move background work to Dispatchers.IO and UI updates to Dispatchers.Main.
Keep the same data flow and error handling logic.
```

### Phase 7 — POST_NOTIFICATIONS permission

```
Refer to docs/migration/migration-guide.md for Kotlin examples and detailed guidance on this change.

Find all places this project shows notifications via NotificationManager.notify().
Add a POST_NOTIFICATIONS runtime permission check before every notify() call
(required on API 33+). Use ActivityResultContracts.RequestPermission to request it.
Also check that PendingIntent flags are FLAG_IMMUTABLE on all notification actions.
```

### Phase 8 — Back navigation

```
Refer to docs/migration/migration-guide.md for Kotlin examples and detailed guidance on this change.

Replace all override fun onBackPressed() implementations with OnBackPressedCallback
registered via onBackPressedDispatcher.addCallback().
Preserve the existing back navigation logic inside the callback's handleOnBackPressed().
```

### Phase 9 — Edge-to-edge insets

```
Refer to docs/migration/migration-guide.md for Kotlin examples and detailed guidance on this change.

Add WindowInsetsCompat handling to all activities in this project.
Apply window insets to the root view or scrollable container so content is not
obscured by the status bar or navigation bar. Use ViewCompat.setOnApplyWindowInsetsListener.
This is required when targeting API 35.
```

### Phase 10 — Splash screen

```
Refer to docs/migration/migration-guide.md for Kotlin examples and detailed guidance on this change.

Remove the custom SplashActivity and replace it with the androidx.core:core-splashscreen
library. Add the dependency to build.gradle, add the Theme.SplashScreen parent to the
app theme in styles.xml, and call installSplashScreen() in MainActivity.onCreate()
before setContentView.
```

### Phase 11 — DataWedge receiver registration (API 33+)

```
Refer to docs/migration/migration-guide.md for Kotlin examples and detailed guidance on this change.

Find all dynamic registerReceiver() calls for DataWedge scan receivers in this project.
Update them to pass RECEIVER_NOT_EXPORTED as the export flag when running on API 33+,
using a Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU check.
DataWedge broadcasts come from a system service and do not require RECEIVER_EXPORTED.
```

### Phase 12 — Build target

```
Refer to docs/migration/migration-guide.md for Kotlin examples and detailed guidance on this change.

Update app/build.gradle (or build.gradle.kts):
- compileSdk 35
- targetSdk 35
- minSdk 30 (or confirm with me if a lower minimum is required)
Add any missing Jetpack dependencies needed for the changes made in earlier phases
(activity-ktx, core-splashscreen, etc.).
```

---

## Automate with Claude Code

Run the full migration non-interactively using the `-p` flag. Create `migrate.sh` in your Android project root:

```bash
#!/bin/bash
set -e

# Usage:
#   ./migrate.sh            — apply all phases
#   ./migrate.sh --dry-run  — print what would run, make no changes

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

LOG="migrate.log"
: > "$LOG"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
run_phase() {
  local label="$1" prompt="$2"
  log "=== $label ==="
  if $DRY_RUN; then
    log "DRY RUN — would run: claude -p \"${prompt:0:80}...\" --allowedTools Edit,Read,Glob,Grep"
  else
    claude -p "$prompt" --allowedTools Edit,Read,Glob,Grep 2>&1 | tee -a "$LOG"
    log "$label complete"
  fi
  echo "" >> "$LOG"
}

log "migrate.sh — Android API 35 migration"
log "Mode: $( $DRY_RUN && echo 'DRY RUN' || echo 'LIVE' )"
log "============================================="

# Run Phase 0 manually in Claude Code first to understand scope before running this script.

run_phase "Phase 1: android:exported" \
  "Refer to docs/migration/migration-guide.md for guidance. Scan AndroidManifest.xml and add android:exported to every activity, service, receiver, and provider that has an intent-filter but is missing the attribute. Use false for internal components, true only for components that must accept external intents."

run_phase "Phase 2: PendingIntent FLAG_IMMUTABLE" \
  "Refer to docs/migration/migration-guide.md for guidance. Find all PendingIntent.getActivity, getBroadcast, and getService calls missing FLAG_IMMUTABLE and add it. Only use FLAG_MUTABLE where genuinely required."

run_phase "Phase 3: Activity Results" \
  "Refer to docs/migration/migration-guide.md for guidance. Replace all startActivityForResult and onActivityResult usage with registerForActivityResult using ActivityResultContracts. Keep existing business logic."

run_phase "Phase 4: Permission Results" \
  "Refer to docs/migration/migration-guide.md for guidance. Replace all onRequestPermissionsResult overrides with registerForActivityResult using ActivityResultContracts.RequestPermission or RequestMultiplePermissions."

run_phase "Phase 5: Storage paths" \
  "Refer to docs/migration/migration-guide.md for guidance. Find and replace hardcoded external storage paths and Environment.getExternalStorageDirectory() usage. Migrate to getExternalFilesDir() for app-private files and MediaStore for shared media."

run_phase "Phase 6: AsyncTask" \
  "Refer to docs/migration/migration-guide.md for guidance. Replace all AsyncTask subclasses with Kotlin coroutines using viewModelScope or lifecycleScope. Move IO work to Dispatchers.IO."

run_phase "Phase 7: POST_NOTIFICATIONS" \
  "Refer to docs/migration/migration-guide.md for guidance. Add POST_NOTIFICATIONS permission check before all NotificationManager.notify() calls. Add the permission to AndroidManifest.xml."

run_phase "Phase 8: Back navigation" \
  "Refer to docs/migration/migration-guide.md for guidance. Replace all onBackPressed() overrides with OnBackPressedCallback registered via onBackPressedDispatcher.addCallback()."

run_phase "Phase 9: Edge-to-edge insets" \
  "Refer to docs/migration/migration-guide.md for guidance. Add WindowInsetsCompat inset handling to all activities so content is not obscured by system bars. Required for targetSdk 35."

run_phase "Phase 10: Splash screen" \
  "Refer to docs/migration/migration-guide.md for guidance. Remove custom SplashActivity and replace with androidx.core:core-splashscreen. Add the dependency, update the theme, and call installSplashScreen() in MainActivity."

run_phase "Phase 11: DataWedge receiver flag" \
  "Refer to docs/migration/migration-guide.md for guidance. Update all registerReceiver calls for DataWedge scan receivers to pass RECEIVER_NOT_EXPORTED on API 33+ with a Build.VERSION.SDK_INT check."

run_phase "Phase 12: Build target" \
  "Refer to docs/migration/migration-guide.md for guidance. Update build.gradle to compileSdk 35, targetSdk 35, minSdk 30. Add any Jetpack dependencies required by the changes made in previous phases."

log "============================================="
log "Migration complete. Full log: $LOG"
$DRY_RUN && log "Dry run — no changes were made."
```

Run it on a clean branch:

```bash
git checkout -b migrate/android-15
chmod +x migrate.sh

# Preview what will run without making changes
./migrate.sh --dry-run

# Run for real
./migrate.sh

# Review all changes before committing
git diff
```

The script logs all output to `migrate.log` in your project root. Review it alongside `git diff` to understand what changed and what may need manual attention.

---

## Practice App

**[android-migration-sample](https://github.com/cbolen/android-migration-sample)** — A legacy inventory app with intentional API 30-era anti-patterns. Safe sandbox for practising the guide before touching production code.

**[examples/example-migration-plan.md](examples/example-migration-plan.md)** — The Phase 0 output from running the discovery prompt against the sample app. Shows what AI analysis looks like in practice. Note: the sample app was built to contain almost every possible issue — a real app will typically have a much smaller subset.

---

## Reference Docs

| Doc | When to use |
|---|---|
| `docs/toolchain-upgrade.md` | **Start here** if on AGP 4.x or 7.x — upgrade JDK/Gradle/AGP before migrating targetSdk |
| `docs/migration-guide.md` | Full technical reference for all A11–A15 breaking changes with Kotlin examples |
| `docs/datawedge-intents-ref.md` | DataWedge Intent API quick reference |

---

## Support

- Zebra Developer Portal: https://developer.zebra.com
- DataWedge Docs: https://techdocs.zebra.com/datawedge/latest/guide/api/
- EMDK Docs: https://techdocs.zebra.com/emdk-for-android/latest/guide/about/
- AI Suite Docs: https://techdocs.zebra.com/ai-datacapture/latest/about/
- DevRel: developer@zebra.com
