+++
id = "SCAN-004"
title = "Shell scripts (scan.sh, migrate.sh) must work on Windows (Git Bash), macOS, and Linux. Replace GNU-only constructs: grep --include (BSD lacks it), sed -i without backup suffix (BSD requires different syntax), printf with literal \\n concatenation, and non-portable find -o without grouping. Add .gitattributes to enforce LF line endings. Add command -v guard for external tool dependencies. Use #!/usr/bin/env bash shebang and portable date formatting."
priority = "MUST"
status = "in-progress"
+++

Shell scripts (scan.sh, migrate.sh) must work on Windows (Git Bash), macOS, and Linux. Replace GNU-only constructs: grep --include (BSD lacks it), sed -i without backup suffix (BSD requires different syntax), printf with literal \n concatenation, and non-portable find -o without grouping. Add .gitattributes to enforce LF line endings. Add command -v guard for external tool dependencies. Use #!/usr/bin/env bash shebang and portable date formatting.

## Acceptance Criteria

### AC-1: No grep --include usage
- **Given** scan.sh source code
- **When** searched for `grep --include`
- **Then** zero matches are found — all source-file grep uses `find -exec grep` instead

### AC-2: No bare sed -i
- **Given** scan.sh source code
- **When** searched for `sed -i`
- **Then** zero matches are found — all in-place edits use a temp file + mv pattern

### AC-3: Portable shebang
- **Given** scan.sh and migrate.sh
- **When** the shebang line is checked
- **Then** both use `#!/usr/bin/env bash`

### AC-4: LF line endings enforced
- **Given** the repository root
- **When** `.gitattributes` is checked
- **Then** it contains a rule forcing `*.sh` files to LF line endings

### AC-5: find -o properly grouped
- **Given** scan.sh source code
- **When** `find` commands with `-o` are reviewed
- **Then** all `-o` alternatives are wrapped in `\( ... \)` to scope `-maxdepth`

### AC-6: migrate.sh guards for claude CLI
- **Given** migrate.sh source code
- **When** run without `claude` CLI installed
- **Then** it prints a helpful error message with alternatives instead of silently failing

### AC-7: Portable date format
- **Given** scan.sh source code
- **When** `date` is called
- **Then** it uses an explicit format string for consistent output across platforms

## Implementation Tasks

- [ ] `scan.sh` — Replace `grep --include` with `find -exec grep`, replace `sed -i` with temp file pattern, fix `find -o` grouping, fix `printf '%b'` concatenation, portable shebang, portable date format
- [ ] `migrate.sh` — Portable shebang, add `command -v claude` guard with helpful error
- [ ] `.gitattributes` — New file, enforce LF line endings for `*.sh`
