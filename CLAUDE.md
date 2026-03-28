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

## Zebra SDK Guidance

### Barcode / RFID Scanning
- Use **DataWedge** (intent-based) or **EMDK** (direct API) for barcode and RFID scanning on Zebra devices
- **DataWedge** is preferred for new development — scan data arrives via broadcast intent, no scanner code in the app, MDM-configurable without app updates
- **EMDK** is appropriate when direct scanner control is needed (custom decode params, serial/USB, payment hardware)
- Register `BroadcastReceiver` for DataWedge scan results; use DataWedge Intent API (`com.symbol.datawedge.api.ACTION`) to configure profiles programmatically
- Always check `EMDKResults` and release `EMDKManager` in `onDestroy` / `onPause`

### Zebra AI Suite (Android 14+ only)
- Only relevant for apps targeting Android 14 (API 34) and above
- Provides AI-based recognition (barcode, OCR, shelf) via `EntityTrackerAnalyzer`
- Supplements DataWedge for AI recognition scenarios — not a replacement

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

## References
- Android API changes: https://developer.android.com/about/versions
- DataWedge Intent API: https://techdocs.zebra.com/datawedge/latest/guide/api/
- EMDK for Android: https://techdocs.zebra.com/emdk-for-android/latest/guide/about/
- AI Suite SDK: https://techdocs.zebra.com/ai-datacapture/latest/about/
- Zebra SSM: https://techdocs.zebra.com/mx/ssmmgr/