+++
id = "ZEBRA-001"
title = "DataWedge receiver pattern must handle the API 33+ RECEIVER_NOT_EXPORTED flag requirement. The boilerplate, scan rule, and migration guide must all consistently demonstrate passing Context.RECEIVER_NOT_EXPORTED when dynamically registering a BroadcastReceiver for DataWedge scan results on API 33+ targets."
priority = "MUST"
status = "draft"
+++

DataWedge receiver pattern must handle the API 33+ RECEIVER_NOT_EXPORTED flag requirement. The boilerplate, scan rule, and migration guide must all consistently demonstrate passing Context.RECEIVER_NOT_EXPORTED when dynamically registering a BroadcastReceiver for DataWedge scan results on API 33+ targets.

## Acceptance Criteria

### AC-1: Boilerplate uses RECEIVER_NOT_EXPORTED
- **Given** `examples/datawedge-receiver.kt`
- **When** reviewed
- **Then** `registerReceiver()` passes `Context.RECEIVER_NOT_EXPORTED` flag with a comment referencing API 33+ requirement

### AC-2: Scanner detects missing flag
- **Given** a project with `registerReceiver(receiver, intentFilter)` without the export flag, where the IntentFilter includes DataWedge actions
- **When** `scan.sh` is run
- **Then** the missing `RECEIVER_NOT_EXPORTED` flag is reported as `[FOUND]`

### AC-3: Migration guide documents the change
- **Given** `docs/migration-guide.md`
- **When** the DataWedge/API 33 section is reviewed
- **Then** it explains why `RECEIVER_NOT_EXPORTED` is required, shows before/after code, and notes this applies to all dynamically registered DataWedge receivers

### AC-4: Consistency across all three sources
- **Given** the boilerplate, scan rule, and migration guide
- **When** the `registerReceiver()` pattern is compared across all three
- **Then** the flag name, usage pattern, and API level annotation are consistent
