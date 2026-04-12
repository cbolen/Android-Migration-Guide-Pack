+++
id = "TEST-001"
title = "Testing checklist must provide test cases covering all target API levels (30, 31, 33, 34, 35) and Zebra device variants (TC series, MC series, WS50/WS501). Each test case must specify: what to test, which API level and device, expected behavior, and pass/fail criteria. Must cover DataWedge scanning, storage operations, permission dialogs, edge-to-edge rendering, and back navigation."
priority = "SHOULD"
status = "draft"
+++

Testing checklist must provide test cases covering all target API levels (30, 31, 33, 34, 35) and Zebra device variants (TC series, MC series, WS50/WS501). Each test case must specify: what to test, which API level and device, expected behavior, and pass/fail criteria. Must cover DataWedge scanning, storage operations, permission dialogs, edge-to-edge rendering, and back navigation.

## Acceptance Criteria

### AC-1: All API levels covered
- **Given** the testing checklist
- **When** reviewed for API level coverage
- **Then** test cases exist for API 30, 31, 33, 34, and 35

### AC-2: Zebra device variants covered
- **Given** the testing checklist
- **When** reviewed for device coverage
- **Then** test cases specify Zebra TC series (standard handheld), MC series (mobile computer), and WS50/WS501 (square wearable display)

### AC-3: Core functional areas covered
- **Given** the testing checklist
- **When** reviewed for functional coverage
- **Then** it includes test cases for: DataWedge scanning, storage read/write, permission grant/deny flows, edge-to-edge rendering, and back navigation (gesture + button)

### AC-4: Each test case has required fields
- **Given** any individual test case in the checklist
- **When** reviewed
- **Then** it specifies: (1) what to test, (2) target API level and device, (3) expected behavior, (4) pass/fail criteria

### AC-5: Behavioral changes included
- **Given** API behavioral changes that have no code signature (notification cooldown, clipboard toast, audio focus denial)
- **When** the checklist is reviewed
- **Then** these are listed as manual verification items with expected device behavior described
