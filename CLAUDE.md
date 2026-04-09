# Zebra Android App — AI Assistant Context

## Platform
Enterprise Android app targeting Zebra devices (TC, MC, EC, ET series).
The majority of migration changes are standard Android API updates. Zebra-specific SDKs apply where noted.

## Standard Android Migration Rules (primary concern)
- All `PendingIntent` must declare `FLAG_IMMUTABLE` or `FLAG_MUTABLE`
- All manifest components with `intent-filter` must set `android:exported`
- Use `ActivityResultContracts` — never `onRequestPermissionsResult` or `startActivityForResult`
- Request `POST_NOTIFICATIONS` at runtime before any notification (API 33+)
- Use granular media permissions (`READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`) not `READ_EXTERNAL_STORAGE`
- Handle edge-to-edge insets with `WindowInsetsCompat` (enforced API 35)
- Replace `onBackPressed()` with `OnBackPressedCallback`
- No `AsyncTask` — use coroutines or WorkManager
- Storage: use `getExternalFilesDir()`, MediaStore, or SAF — no hardcoded paths, no `MANAGE_EXTERNAL_STORAGE`

## Breaking Changes by API Level

These cause crashes, install failures, or silent data loss. Flag any of these patterns immediately when seen in code.

### API 31 (Android 12)
- **Install failure**: any manifest component with `intent-filter` missing `android:exported`
- **Runtime crash**: `PendingIntent` created without `FLAG_IMMUTABLE` or `FLAG_MUTABLE`
- **Runtime crash**: `Cipher.getInstance(algo, "BC")` — BouncyCastle provider removed; use default provider
- **Silent failure**: notification tapped → `BroadcastReceiver`/`Service` → `startActivity()` is blocked (notification trampoline); attach `PendingIntent` directly to the notification
- **Runtime crash**: `MediaRecorder()` no-arg constructor removed — use `MediaRecorder(context)`
- **Security exception**: `ACTION_CLOSE_SYSTEM_DIALOGS` broadcast blocked — remove any usage
- **Runtime exception**: AES/GCM cipher requires exactly 12-byte IV — any other length throws `InvalidAlgorithmParameterException`
- **Runtime exception**: `AlarmManager.setExact*()` without `SCHEDULE_EXACT_ALARM` permission; check `canScheduleExactAlarms()` before scheduling
- **Blocked**: starting a foreground service while app is in background; use `WorkManager` expedited jobs instead
- **Bluetooth**: `BLUETOOTH`/`BLUETOOTH_ADMIN` replaced by `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`/`BLUETOOTH_ADVERTISE` for API 31+

### API 33 (Android 13)
- **Silent drop**: notifications never shown without `POST_NOTIFICATIONS` runtime permission
- **Crash**: `AsyncTask` removed — replace with coroutines or `WorkManager`
- **Permission denied**: `READ_EXTERNAL_STORAGE` replaced by `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`
- **DataWedge**: dynamic `registerReceiver()` must pass `RECEIVER_NOT_EXPORTED` flag on API 33+
- **Silent failure**: `BluetoothAdapter.enable()`/`disable()` always return `false` on API 33+ targets — prompt user via `ACTION_REQUEST_ENABLE` instead
- **Deprecation**: `getParcelableExtra(key)` and `getSerializableExtra(key)` — use typed variants `getParcelableExtra(key, Class)` / `getSerializableExtra(key, Class)`
- **Deprecation**: `android:sharedUserId` — add `android:sharedUserMaxSdkVersion="32"` if still in use; plan migration to `FileProvider` or content providers

### API 34 (Android 14)
- **Runtime crash**: foreground service with no `foregroundServiceType` declared in manifest
- **Silent revocation**: `SCHEDULE_EXACT_ALARM` is revoked on app update — re-check `canScheduleExactAlarms()` in `onResume`
- **Blocked**: implicit intents targeting internal non-exported components — use explicit intents
- **Permission lost**: `USE_FULL_SCREEN_INTENT` auto-revoked for non-alarm/calling apps — check `canUseFullScreenIntent()` and fall back to `IMPORTANCE_HIGH` notification channel
- **Security exception**: dynamically loaded DEX files must be read-only (`file.setReadOnly()`) before loading
- **ZipException**: `ZipFile`/`ZipInputStream` rejects entries with path traversal (`../`) — validate entry names before extraction

### API 35 (Android 15)
- **Visual regression**: edge-to-edge enforced — content draws behind system bars without `WindowInsetsCompat` inset handling
- **Layout break**: `Configuration.screenWidthDp`/`screenHeightDp` now includes system bar area — use `WindowMetrics` for available content dimensions
- **Audio denied**: audio focus requests from background contexts blocked — ensure audio plays from foreground or a `mediaPlayback` foreground service
- **Install blocked**: apps with `targetSdkVersion` < 24 cannot be installed on Android 15 devices
- **Canceled silently**: `PendingIntent`s are canceled when the package is force-stopped — re-register alarms and scheduled work on next launch
- **TLS failure**: connections to TLS 1.0/1.1 endpoints fail — verify all endpoints support TLS 1.2+
- **Boot service blocked**: `dataSync` and `mediaProcessing` foreground services cannot start from `BOOT_COMPLETED` — use `WorkManager` instead

## Zebra SDK Guidance

### Barcode Scanning
- Use **DataWedge** (intent-based) for all barcode scanning on Zebra devices — scan data arrives via broadcast intent, no scanner code in the app, MDM-configurable without app updates
- Register `BroadcastReceiver` for DataWedge scan results; use DataWedge Intent API (`com.symbol.datawedge.api.ACTION`) to configure profiles programmatically
- **EMDK** is appropriate only when direct scanner control is required (custom decode params, serial/USB, payment hardware); always check `EMDKResults` and release `EMDKManager` in `onDestroy` / `onPause`

### Zebra AI Suite (Android 14+ only)
- Use for advanced data capture scenarios: AI barcode recognition, OCR, shelf analysis via `EntityTrackerAnalyzer`
- Only relevant for apps targeting Android 14 (API 34) and above
- Recommended over DataWedge when AI-based recognition is needed — use alongside DataWedge for standard scanning

## Storage Rules
- `getExternalFilesDir()` — app-specific files, no permission needed
- MediaStore — shared media and downloads
- SAF (`ACTION_OPEN_DOCUMENT`) — user-selected files
- SSM (Secure Storage Manager) — only when sharing files at fixed paths across multiple enterprise apps on Zebra devices

## Do Not
- Use `onBackPressed()` override (deprecated)
- Use `AsyncTask` (removed API 33)
- Use `startActivityForResult` / `onActivityResult` (deprecated)
- Hardcode external storage paths (`/sdcard/`, `/storage/emulated/0/`)
- Suggest `MANAGE_EXTERNAL_STORAGE` for standard storage patterns

## Full Migration Reference

For complete migration guidance including code examples, behavioral changes, system UI differences, Zebra device-specific notes (WS50/WS501 square display, EMDK service binding, DataWedge profile association), and the phase-by-phase testing checklist, read:

- **`docs/migration-guide.md`** — full A11→A15 reference with Kotlin examples for every change above
- **`docs/datawedge-intents-ref.md`** — DataWedge Intent API quick reference

Consult these files when: helping with a migration task, reviewing code for API compatibility issues, or answering questions about specific Android version behavior.

## References
- Android API changes: https://developer.android.com/about/versions
- DataWedge Intent API: https://techdocs.zebra.com/datawedge/latest/guide/api/
- EMDK for Android: https://techdocs.zebra.com/emdk-for-android/latest/guide/about/
- AI Suite SDK: https://techdocs.zebra.com/ai-datacapture/latest/about/
- Zebra SSM: https://techdocs.zebra.com/mx/ssmmgr/