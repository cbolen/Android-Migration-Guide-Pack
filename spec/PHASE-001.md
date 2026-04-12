+++
id = "PHASE-001"
title = "Each migration phase (Phase 0 through Phase 12) must define: prerequisites (which phases must be complete), scope (which scan rules or breaking changes it addresses), expected deliverable (code changes or artifacts produced), and pass criteria (how to verify the phase is complete)."
priority = "SHOULD"
status = "draft"
+++

Each migration phase (Phase 0 through Phase 12) must define: prerequisites (which phases must be complete), scope (which scan rules or breaking changes it addresses), expected deliverable (code changes or artifacts produced), and pass criteria (how to verify the phase is complete).

## Acceptance Criteria

### AC-1: Prerequisites defined for each phase
- **Given** any phase (Phase 0-12) in the migration guide or README
- **When** reviewed
- **Then** it lists which prior phases must be complete before starting (Phase 0 has none)

### AC-2: Scope maps to scan rules or breaking changes
- **Given** any phase
- **When** its scope is reviewed
- **Then** it references specific breaking changes by API level or scan rule IDs that the phase addresses

### AC-3: Deliverable is concrete
- **Given** any phase
- **When** its deliverable is reviewed
- **Then** it specifies tangible output: code changes committed, manifest edits, build file updates, or test results recorded

### AC-4: Pass criteria are verifiable
- **Given** any phase
- **When** its pass criteria are reviewed
- **Then** the criteria can be checked mechanically (e.g., "scan.sh reports [OK] for all Phase N rules") or by specific manual test (e.g., "notification appears on API 33 device after granting POST_NOTIFICATIONS")

### AC-5: All 13 phases covered
- **Given** the complete documentation set
- **When** phases are enumerated
- **Then** Phase 0 (discovery) through Phase 12 (testing) each have prerequisites, scope, deliverable, and pass criteria
