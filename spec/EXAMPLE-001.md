+++
id = "EXAMPLE-001"
title = "All Kotlin boilerplate examples in the examples/ directory must be syntactically valid Kotlin, use current Jetpack and Android API conventions, target API 35 compatibility, and include inline comments explaining Zebra-specific or migration-critical lines."
priority = "MUST"
status = "draft"
+++

All Kotlin boilerplate examples in the examples/ directory must be syntactically valid Kotlin, use current Jetpack and Android API conventions, target API 35 compatibility, and include inline comments explaining Zebra-specific or migration-critical lines.

## Acceptance Criteria

### AC-1: Syntactic validity
- **Given** any `.kt` file in `examples/`
- **When** parsed by the Kotlin compiler
- **Then** it produces no syntax errors

### AC-2: API 35 compatibility
- **Given** any example targeting Android APIs
- **When** reviewed for deprecated or removed API usage
- **Then** it uses only APIs available at `targetSdkVersion 35` (e.g., `OnBackPressedCallback` not `onBackPressed()`, `ActivityResultContracts` not `startActivityForResult`)

### AC-3: Migration-critical lines annotated
- **Given** any line in an example that addresses a specific migration concern (e.g., `RECEIVER_NOT_EXPORTED` flag, `FLAG_IMMUTABLE`, `WindowInsetsCompat`)
- **When** reviewed
- **Then** the line has an inline comment explaining why it is required and which API level enforces it

### AC-4: All six example files present
- **Given** the `examples/` directory
- **When** listed
- **Then** it contains: `datawedge-receiver.kt`, `edge-to-edge-insets.kt`, `emdk-scanner-basic.kt`, `permissions-compat.kt`, `storage-patterns.kt`, `datawedge-api-commands.kt`
