+++
id = "SCAN-001"
title = "Scanner must detect all documented breaking changes across API levels 31, 33, 34, and 35 as listed in migration-guide.md. Every breaking change that causes a crash, install failure, silent data loss, or permission denial must have a corresponding scan rule in scan.sh."
priority = "MUST"
status = "draft"
+++

Scanner must detect all documented breaking changes across API levels 31, 33, 34, and 35 as listed in migration-guide.md. Every breaking change that causes a crash, install failure, silent data loss, or permission denial must have a corresponding scan rule in scan.sh.

## Acceptance Criteria

### AC-1: API 31 breaking changes detected
- **Given** a project with code patterns matching any API 31 breaking change (missing `android:exported`, `PendingIntent` without flags, BouncyCastle provider, notification trampoline, `MediaRecorder()` no-arg, `ACTION_CLOSE_SYSTEM_DIALOGS`, AES/GCM non-12-byte IV, exact alarm without permission, background foreground service, legacy Bluetooth permissions, custom SplashActivity)
- **When** `scan.sh` is run against the project
- **Then** each pattern is reported as `[FOUND]` or `[VERIFY]` with the correct rule ID

### AC-2: API 33 breaking changes detected
- **Given** a project using `AsyncTask`, `registerReceiver()` without export flag, `BluetoothAdapter.enable()`, untyped `getParcelableExtra()`, missing `POST_NOTIFICATIONS`, `READ_EXTERNAL_STORAGE`, or `sharedUserId`
- **When** `scan.sh` is run against the project
- **Then** each pattern is reported with the correct category and rule ID

### AC-3: API 34 breaking changes detected
- **Given** a project with foreground services missing `foregroundServiceType`, missing `canScheduleExactAlarms()` re-check, non-read-only DEX loading, `ZipFile` without path traversal validation, or `USE_FULL_SCREEN_INTENT` usage
- **When** `scan.sh` is run against the project
- **Then** each pattern is reported with the correct category and rule ID

### AC-4: API 35 breaking changes detected
- **Given** a project using `onBackPressed()`, `startActivityForResult`/`onActivityResult`, missing `WindowInsetsCompat`, `screenWidthDp`/`screenHeightDp` usage, or TLS 1.0/1.1 endpoints
- **When** `scan.sh` is run against the project
- **Then** each pattern is reported with the correct category and rule ID

### AC-5: No documented breaking change left uncovered
- **Given** the full list of breaking changes in `docs/migration-guide.md`
- **When** each breaking change is cross-referenced against `scan.sh` rule set
- **Then** every change with a detectable code/manifest pattern has a corresponding scan rule
