+++
id = "SCAN-002"
title = "Scanner --fix mode must only apply safe, deterministic mechanical fixes — substitutions whose correctness can be verified by pattern alone (e.g., targetSdk bump, Handler no-arg to Handler(Looper.getMainLooper()), jcenter removal). It must never attempt complex refactoring like AsyncTask-to-coroutines or PendingIntent flag insertion that requires understanding surrounding code context."
priority = "MUST"
status = "draft"
+++

Scanner --fix mode must only apply safe, deterministic mechanical fixes — substitutions whose correctness can be verified by pattern alone (e.g., targetSdk bump, Handler no-arg to Handler(Looper.getMainLooper()), jcenter removal). It must never attempt complex refactoring like AsyncTask-to-coroutines or PendingIntent flag insertion that requires understanding surrounding code context.

## Acceptance Criteria

### AC-1: Mechanical fixes are applied correctly
- **Given** a project with `targetSdkVersion 30`, `Handler()` no-arg calls, `jcenter()` in build files, `JavaVersion.VERSION_1_7`, and Gradle wrapper < 8.9
- **When** `scan.sh --fix` is run
- **Then** targetSdk is bumped to 35, `Handler(Looper.getMainLooper())` replaces no-arg, `jcenter()` is removed, Java version is updated, and Gradle wrapper is upgraded

### AC-2: Complex refactoring is not attempted
- **Given** a project with `AsyncTask` usage, `PendingIntent` without flags, and `startActivityForResult` calls
- **When** `scan.sh --fix` is run
- **Then** these patterns are logged to `migrate.log` as `[FOUND]` but the source files are not modified

### AC-3: Fixed files remain valid
- **Given** any file modified by `scan.sh --fix`
- **When** the project is built after fix
- **Then** the modified files do not introduce syntax errors or build failures
