# Zebra Android Migration — AI Assistant Context

Paste this entire file as your first message when using any AI chat tool (ChatGPT, Gemini, Claude.ai, Copilot Chat, etc.) to get Zebra-aware assistance.

---

## Context for AI Assistant

You are helping update an Android application that runs on Zebra enterprise devices (TC, MC, EC, ET series). The migration target is Android 11 (API 30) through Android 15 (API 35).

The **majority of changes are standard Android API migrations** — the same updates any Android app requires. Zebra-specific guidance applies in addition to, not instead of, standard Android best practices.

### Build Target
- `minSdk`: 30 (Android 11) or higher
- `targetSdk`: 35 (Android 15)
- `compileSdk`: 35
- Language: Kotlin preferred, Java acceptable

### How to Use This File

**This file is for AI chat tools (Claude.ai, ChatGPT, Gemini, Copilot Chat) that do not have
direct access to your filesystem.** Paste this entire file as your first message, then paste
the files you want help with — at minimum your `AndroidManifest.xml` and `build.gradle`, plus
any source files relevant to the task.

If you are using **Claude Code, Cursor, or GitHub Copilot** inside your IDE: drop `CLAUDE.md`
in your project root instead — those tools read your project files directly and do not need
this paste-based approach. See `docs/how-to-use.md` for setup instructions.

For the **full migration reference** (code examples, per-API-level change lists, Zebra device
notes): paste the contents of `docs/migration-guide.md` after this file in the same message.

---

### Recommended First Step — Project Audit

Before making any changes, paste your project files and ask for a migration plan.

> Paste `AndroidManifest.xml`, `build.gradle`, and your key source files into the conversation
> first, then use the prompt below.

```
I have pasted the Zebra migration context and my project files above.

Review the files I have pasted and produce a migration plan with the following sections:

1. BLOCKING ISSUES (causes install failure or runtime crash)
   - List each issue, the file and line, the API level that breaks it, and the fix needed

2. REQUIRED CHANGES (behaviour breaks silently or permission is denied)
   - List each issue, the file and line, the API level that enforces it, and the fix needed

3. ZEBRA-SPECIFIC ISSUES
   - DataWedge receiver registration, EMDK lifecycle, storage patterns, AI Suite eligibility

4. RECOMMENDED TESTS
   - Per change area: what to test, on which API level, and what a pass looks like

5. SUGGESTED PHASE ORDER
   - Recommend which changes to tackle first and in what order, starting with anything
     that causes install failure or a runtime crash

Do not make any changes. Output the plan only.
```

Review and confirm the plan before making any changes.

---

### Standard Android Migration Priorities (primary — work in this order)
1. Set `android:exported` on all manifest components with `intent-filter`
2. Add `FLAG_IMMUTABLE` or `FLAG_MUTABLE` to all `PendingIntent` calls
3. Replace `startActivityForResult` / `onActivityResult` with `registerForActivityResult`
4. Replace `onRequestPermissionsResult` with `ActivityResultContracts.RequestPermission`
5. Replace `READ_EXTERNAL_STORAGE` with granular media permissions (`READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`)
6. Add `POST_NOTIFICATIONS` runtime permission request
7. Migrate file writes to `getExternalFilesDir()` or MediaStore
8. Replace `onBackPressed()` with `OnBackPressedCallback`
9. Add edge-to-edge inset handling with `WindowInsetsCompat`
10. Remove custom splash Activity — use `androidx.core:core-splashscreen`

### Zebra SDK Guidance

**Barcode Scanning**
- Use **DataWedge** for all barcode scanning on Zebra devices — scan data arrives via broadcast intent, MDM-configurable without app changes
- **EMDK** only when direct scanner control is required (custom decode params, serial/USB, payment hardware)

DataWedge intent pattern:
```kotlin
class ScanReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val data = intent.getStringExtra("com.symbol.datawedge.data_string")
        val symbology = intent.getStringExtra("com.symbol.datawedge.label_type")
    }
}

fun sendDataWedgeCommand(context: Context, key: String, value: String) {
    Intent("com.symbol.datawedge.api.ACTION").also {
        it.putExtra(key, value)
        context.sendBroadcast(it)
    }
}
```

**Zebra AI Suite (Android 14+ only)**
- Use for advanced data capture: AI barcode recognition, OCR, shelf analysis
- Recommended over DataWedge when AI-based recognition is needed — use alongside DataWedge for standard scanning
- Only relevant for apps targeting Android 14 (API 34) and above

### Storage Rules
- `getExternalFilesDir()` — app-specific files, no permission needed
- MediaStore — shared media and downloads
- SAF (`ACTION_OPEN_DOCUMENT`) — user-selected files
- No hardcoded `/sdcard/` or `/storage/emulated/0/` paths
- No `MANAGE_EXTERNAL_STORAGE` for standard patterns
- SSM (Zebra Secure Storage Manager) — only if sharing files at deterministic paths across multiple enterprise apps

### Jetpack Compatibility — Always Prefer
| Instead of | Use |
|---|---|
| `onBackPressed()` | `OnBackPressedCallback` (activity-ktx 1.8+) |
| `startActivityForResult` | `registerForActivityResult` |
| `AsyncTask` | Coroutines or `WorkManager` |
| `SharedPreferences` | `DataStore` |
| Raw `WindowInsets` | `WindowInsetsCompat` |
| Custom splash `Activity` | `core-splashscreen` library |

### Do Not Suggest
- `MANAGE_EXTERNAL_STORAGE` for standard app storage
- `onBackPressed()` override
- `AsyncTask`
- `startActivityForResult` / `onActivityResult`
- Hardcoded external storage paths