+++
id = "SCAN-003"
title = "Scanner must categorize findings as [FOUND] (high-confidence issue requiring change), [VERIFY] (pattern detected but may already be correct), or [OK] (pattern not found). The [VERIFY] category must be used when the detection regex matches but correctness requires manual review (e.g., intent-filter present but exported flag may already exist)."
priority = "SHOULD"
status = "draft"
+++

Scanner must categorize findings as [FOUND] (high-confidence issue requiring change), [VERIFY] (pattern detected but may already be correct), or [OK] (pattern not found). The [VERIFY] category must be used when the detection regex matches but correctness requires manual review (e.g., intent-filter present but exported flag may already exist).

## Acceptance Criteria

### AC-1: FOUND used for high-confidence issues
- **Given** a project where `AsyncTask` is used (removed in API 33) or `onBackPressed()` is overridden
- **When** `scan.sh` is run
- **Then** the finding is categorized as `[FOUND]` because the pattern unambiguously indicates a required change

### AC-2: VERIFY used for ambiguous patterns
- **Given** a project with `intent-filter` elements in the manifest (which may or may not already have `android:exported`)
- **When** `scan.sh` is run
- **Then** the finding is categorized as `[VERIFY]` because the pattern requires human confirmation

### AC-3: OK used for absent patterns
- **Given** a project with no `AsyncTask` usage
- **When** `scan.sh` is run
- **Then** the AsyncTask check reports `[OK]`

### AC-4: Every scanner output line uses exactly one category
- **Given** any `scan.sh` execution
- **When** the output is parsed
- **Then** every finding line contains exactly one of `[FOUND]`, `[VERIFY]`, or `[OK]`
