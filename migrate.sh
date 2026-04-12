#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# migrate.sh — AI-assisted Android migration (Claude Code)
# Run scan.sh --fix first to generate migrate.log before running this script.
#
# Usage:
#   bash migrate.sh            — apply fixes
#   bash migrate.sh --dry-run  — print what would run, make no changes
# ─────────────────────────────────────────────────────────────────────────────
set -e

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

ROOT="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -f "$ROOT/migrate.log" ]]; then
  echo "ERROR: migrate.log not found. Run scan.sh --fix first."
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: claude CLI not found. Install from https://claude.ai/download"
  echo ""
  echo "Alternatively, paste migrate.log and docs/migration-guide.md into"
  echo "ChatGPT, Gemini, or Claude.ai and ask the AI to apply fixes."
  exit 1
fi

if $DRY_RUN; then
  echo "DRY RUN — would run:"
  echo "  claude -p \"Read migrate.log and docs/migration/migration-guide.md."
  echo "  Apply fixes for every [FOUND] item, one at a time. Commit after each fix.\""
  exit 0
fi

claude -p "Read migrate.log for the list of items needing fixes in this project. \
Read docs/migration/migration-guide.md for guidance and Kotlin examples. \
Apply fixes for every [FOUND] item in migrate.log, one at a time. Commit after each fix. \
When all fixes are done, output a TESTING CHECKLIST: for each fix applied, one row with \
what to test, which API level or device to test on, and the pass criteria." \
--allowedTools Edit,Read,Glob,Grep,Bash
