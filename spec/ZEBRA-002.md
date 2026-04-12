+++
id = "ZEBRA-002"
title = "EMDK examples must demonstrate proper lifecycle management: acquire EMDKManager in onCreate, release in onDestroy or onPause, check EMDKResults on every API call, and handle the EMDK service not being available (non-Zebra device or service crash). The pattern must prevent resource leaks and handle rebinding after process death."
priority = "SHOULD"
status = "draft"
+++

EMDK examples must demonstrate proper lifecycle management: acquire EMDKManager in onCreate, release in onDestroy or onPause, check EMDKResults on every API call, and handle the EMDK service not being available (non-Zebra device or service crash). The pattern must prevent resource leaks and handle rebinding after process death.

## Acceptance Criteria

### AC-1: Lifecycle acquire and release
- **Given** `examples/emdk-scanner-basic.kt`
- **When** reviewed
- **Then** `EMDKManager` is acquired via `EMDKManager.getEMDKManager()` in `onCreate` and released via `emdkManager.release()` in `onDestroy`

### AC-2: EMDKResults checked
- **Given** any EMDK API call in the example
- **When** the call is made
- **Then** the `EMDKResults.STATUS_CODE` is checked and non-success results are handled (logged or surfaced to user)

### AC-3: Non-Zebra device handling
- **Given** the example is run on a non-Zebra device or emulator where EMDK service is unavailable
- **When** `getEMDKManager()` fails
- **Then** the failure is caught and the app degrades gracefully (no crash, shows appropriate message)

### AC-4: No resource leaks
- **Given** the Activity lifecycle: `onCreate` -> `onPause` -> `onDestroy`
- **When** the lifecycle completes
- **Then** all EMDK scanner objects and the EMDKManager itself are released, with no lingering references
