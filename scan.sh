#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# scan.sh — Android migration pattern scanner
#
# Scans the project for patterns requiring migration to Android 15 (API 35).
# Default: scan only — no changes made, findings written to migrate.log.
# --fix:   apply mechanical fixes (safe, deterministic substitutions only),
#          then write remaining items to migrate.log for AI to handle.
#
# Works with any AI tool:
#   - Claude Code / Cursor / Copilot: run scan.sh [--fix], then run migrate.sh
#   - ChatGPT / Gemini / Claude.ai:   run scan.sh [--fix], paste migrate.log
#
# Usage:
#   bash scan.sh          — scan only, no changes
#   bash scan.sh --fix    — apply mechanical fixes + scan remaining
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

FIX=false
[[ "${1:-}" == "--fix" ]] && FIX=true

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOG="$ROOT/migrate.log"
: > "$LOG"
FOUND=0
FIXED=0

log()   { echo "$*" | tee -a "$LOG"; }
found() { FOUND=$((FOUND+1)); log "  [FOUND]  $*"; }
fixed() { FIXED=$((FIXED+1)); log "  [FIXED]  $*"; }
ok()    { log "  [OK]     $*"; }

scan_src() {
  local pattern="$1" msg="$2"
  local hits
  hits=$(grep -rn --include='*.java' --include='*.kt' -E "$pattern" "$ROOT/app/src" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    found "$msg"
    echo "$hits" | while IFS= read -r line; do log "             $line"; done
  else
    ok "$msg"
  fi
}

scan_manifest() {
  local pattern="$1" msg="$2"
  [[ ! -f "$MANIFEST" ]] && { log "  [SKIP]   $msg (manifest not found)"; return; }
  local hits
  hits=$(grep -n -E "$pattern" "$MANIFEST" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    found "$msg"
    echo "$hits" | while IFS= read -r line; do log "             AndroidManifest.xml:$line"; done
  else
    ok "$msg"
  fi
}

# Mechanical fix: replace text in a file (idempotent — skips if old text absent)
mfix() {
  local file="$1" old="$2" new="$3" desc="$4"
  [[ ! -f "$file" ]] && return
  if grep -qF "$old" "$file" 2>/dev/null; then
    if $FIX; then
      sed -i "s|$(echo "$old" | sed 's/[&/\]/\\&/g')|$(echo "$new" | sed 's/[&/\]/\\&/g')|g" "$file"
      fixed "$desc"
    else
      found "$desc (--fix will apply this automatically)"
    fi
  else
    ok "$desc"
  fi
}

# Mechanical fix across all source files matching a pattern
mfix_src() {
  local pattern="$1" old="$2" new="$3" desc="$4"
  local files
  files=$(grep -rln --include='*.java' --include='*.kt' -F "$old" "$ROOT/app/src" 2>/dev/null || true)
  if [[ -n "$files" ]]; then
    if $FIX; then
      echo "$files" | while IFS= read -r f; do
        sed -i "s|$(echo "$old" | sed 's/[&/\]/\\&/g')|$(echo "$new" | sed 's/[&/\]/\\&/g')|g" "$f"
      done
      fixed "$desc"
    else
      found "$desc (--fix will apply this automatically)"
      echo "$files" | while IFS= read -r f; do log "             $f"; done
    fi
  else
    ok "$desc"
  fi
}

# ── Auto-detect project layout ────────────────────────────────────────────────
APP_BUILD=$(find "$ROOT" -maxdepth 2 -name "build.gradle" -path "*/app/*" | head -1)
MANIFEST=$(find "$ROOT" -path "*/src/main/AndroidManifest.xml" | head -1)
SETTINGS=$(find "$ROOT" -maxdepth 1 -name "settings.gradle" -o -name "settings.gradle.kts" | head -1)
WRAPPER="$ROOT/gradle/wrapper/gradle-wrapper.properties"

[[ -z "$APP_BUILD" ]] && { echo "ERROR: app/build.gradle not found"; exit 1; }
[[ -z "$MANIFEST" ]]  && { echo "ERROR: AndroidManifest.xml not found"; exit 1; }

CURRENT_TARGET=$(grep 'targetSdk' "$APP_BUILD" 2>/dev/null | sed 's/[^0-9]//g' | head -1)

log "============================================="
log "scan.sh — Android migration scanner"
log "Mode      : $( $FIX && echo 'SCAN + FIX mechanical' || echo 'SCAN ONLY' )"
log "Project   : $ROOT"
log "targetSdk : ${CURRENT_TARGET:-unknown}"
log "Scan date : $(date)"
log "============================================="
log ""

# ── Mechanical fixes (--fix only) ─────────────────────────────────────────────
log "=== BUILD (mechanical) ==="

# targetSdk / compileSdk bump
for sdk in targetSdk compileSdk; do
  val=$(grep "$sdk" "$APP_BUILD" 2>/dev/null | sed 's/[^0-9]//g' | head -1)
  if [[ -n "$val" && "$val" -lt 35 ]]; then
    mfix "$APP_BUILD" "${sdk} ${val}" "${sdk} 35" "${sdk} ${val} → 35"
    mfix "$APP_BUILD" "${sdk}Version ${val}" "${sdk} 35" "${sdk}Version ${val} → ${sdk} 35 (integer form)"
  else
    ok "${sdk} already 35"
  fi
done

# Java compat → 17
for level in VERSION_1_7 VERSION_1_8 VERSION_11; do
  mfix "$APP_BUILD" "$level" "VERSION_17" "Java compat $level → VERSION_17"
done

# Remove jcenter()
if [[ -n "$SETTINGS" ]] && grep -q 'jcenter()' "$SETTINGS" 2>/dev/null; then
  if $FIX; then
    sed -i '/jcenter()/d' "$SETTINGS"
    fixed "Removed jcenter() from $(basename "$SETTINGS")"
  else
    found "jcenter() present — deprecated, remove from $(basename "$SETTINGS") (--fix will remove automatically)"
  fi
else
  ok "jcenter() not present"
fi

# Gradle wrapper → 8.x
if [[ -f "$WRAPPER" ]] && grep -qE 'gradle-[67]\.' "$WRAPPER" 2>/dev/null; then
  if $FIX; then
    sed -i 's|distributionUrl=.*|distributionUrl=https\\://services.gradle.org/distributions/gradle-8.9-bin.zip|' "$WRAPPER"
    fixed "Gradle wrapper → 8.9"
  else
    found "Gradle wrapper is pre-8.x — upgrade to 8.x+ for AGP 8 / targetSdk 35 (--fix will update automatically)"
  fi
else
  ok "Gradle wrapper 8.x+"
fi

# ── Source mechanical fixes ────────────────────────────────────────────────────
log ""
log "=== SOURCE (mechanical) ==="
mfix_src 'Handler()' 'Handler()' 'Handler(android.os.Looper.getMainLooper())' \
  "Handler() no-arg → Handler(Looper.getMainLooper())"

# ── API 31 (Android 12) ───────────────────────────────────────────────────────
log ""
log "=== API 31 (Android 12) ==="
scan_manifest 'intent-filter' \
  "Components with intent-filter — verify android:exported is set on each (install failure if missing)"
scan_src 'PendingIntent\.(getActivity|getBroadcast|getService|getForegroundService)' \
  "PendingIntent calls — verify FLAG_IMMUTABLE or FLAG_MUTABLE on every call (runtime crash)"
scan_src 'Cipher\.getInstance.*"BC"' \
  "BouncyCastle provider — removed API 31, use default provider"
scan_src 'setExactAndAllowWhileIdle|setAlarmClock|\.setExact\(' \
  "Exact alarm — requires SCHEDULE_EXACT_ALARM permission + canScheduleExactAlarms() guard"
scan_manifest 'SCHEDULE_EXACT_ALARM|USE_EXACT_ALARM' \
  "Exact alarm permission declared in manifest"
scan_src 'ACTION_CLOSE_SYSTEM_DIALOGS' \
  "ACTION_CLOSE_SYSTEM_DIALOGS — throws SecurityException on API 31+"
scan_src 'MediaRecorder\(\)' \
  "MediaRecorder() no-arg constructor — removed API 31, use MediaRecorder(context)"
scan_src 'GCMParameterSpec|AES/GCM' \
  "AES/GCM cipher — verify exactly 12-byte IV (any other length throws on API 31)"

# ── API 33 (Android 13) ───────────────────────────────────────────────────────
log ""
log "=== API 33 (Android 13) ==="
scan_src 'AsyncTask' \
  "AsyncTask — removed API 33, replace with coroutines or WorkManager"
scan_src 'registerReceiver\(' \
  "registerReceiver() — must pass RECEIVER_NOT_EXPORTED or RECEIVER_EXPORTED on API 33+"
scan_src 'BluetoothAdapter.*\.enable\(\)|BluetoothAdapter.*\.disable\(\)' \
  "BluetoothAdapter.enable/disable() — always returns false on API 33+, use ACTION_REQUEST_ENABLE"
scan_src 'getParcelableExtra\("[^"]*"\)' \
  "getParcelableExtra(key) untyped — use getParcelableExtra(key, Class) on API 33+"
scan_src 'getSerializableExtra\("[^"]*"\)' \
  "getSerializableExtra(key) untyped — use getSerializableExtra(key, Class) on API 33+"
scan_manifest 'POST_NOTIFICATIONS' \
  "POST_NOTIFICATIONS permission in manifest (required API 33+)"
scan_manifest 'READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE' \
  "Legacy storage permissions — replace with READ_MEDIA_IMAGES/VIDEO/AUDIO on API 33+"

# ── API 34 (Android 14) ───────────────────────────────────────────────────────
log ""
log "=== API 34 (Android 14) ==="
scan_manifest '<service' \
  "Service declarations — verify foregroundServiceType is set on each (runtime crash if missing)"
scan_manifest 'foregroundServiceType' \
  "foregroundServiceType declared (cross-check with service count above)"
scan_src 'canScheduleExactAlarms' \
  "canScheduleExactAlarms() — verify check is also in onResume (auto-revoked on app update)"
scan_src 'DexClassLoader|PathClassLoader|InMemoryDexClassLoader' \
  "Dynamic DEX loading — file must be setReadOnly() before loading on API 34+"
scan_src 'ZipFile|ZipInputStream' \
  "ZipFile/ZipInputStream — validate entry names against path traversal on API 34+"
scan_manifest 'USE_FULL_SCREEN_INTENT' \
  "USE_FULL_SCREEN_INTENT — auto-revoked for non-alarm/calling apps on API 34+"

# ── API 35 (Android 15) ───────────────────────────────────────────────────────
log ""
log "=== API 35 (Android 15) ==="
scan_src 'override fun onBackPressed|public void onBackPressed' \
  "onBackPressed() override — replace with OnBackPressedCallback (predictive back enforced)"
scan_src 'startActivityForResult|onActivityResult|onRequestPermissionsResult' \
  "Deprecated result APIs — replace with ActivityResultContracts"
scan_src 'WindowInsetsCompat|setOnApplyWindowInsetsListener' \
  "Edge-to-edge inset handling — verify all activities covered (enforced API 35)"
scan_src 'screenWidthDp|screenHeightDp' \
  "Configuration.screenWidthDp/heightDp — now includes system bars, use WindowMetrics"
scan_src 'TLSv1[^2]|SSLv3' \
  "TLS 1.0/1.1 usage — connections blocked on API 35, verify all endpoints support TLS 1.2+"

# ── Storage ───────────────────────────────────────────────────────────────────
log ""
log "=== STORAGE ==="
scan_src '/sdcard/|/storage/emulated/0/' \
  "Hardcoded storage paths — use getExternalFilesDir() or MediaStore"
scan_src 'getExternalStorageDirectory|getExternalStoragePublicDirectory' \
  "Legacy external storage APIs — use getExternalFilesDir() or MediaStore"
scan_manifest 'MANAGE_EXTERNAL_STORAGE' \
  "MANAGE_EXTERNAL_STORAGE — evaluate if scoped storage can replace"

# ── Zebra-specific ────────────────────────────────────────────────────────────
log ""
log "=== ZEBRA-SPECIFIC ==="
scan_src 'com\.symbol\.datawedge|DataWedge|datawedge' \
  "DataWedge usage — verify receiver uses RECEIVER_NOT_EXPORTED on API 33+"
scan_src 'RECEIVER_NOT_EXPORTED|RECEIVER_EXPORTED' \
  "DataWedge receiver export flag present"
scan_src 'EMDKManager|EMDKResults|emdkManager' \
  "EMDK usage — verify EMDKManager released in onPause/onDestroy"

# ── Summary ───────────────────────────────────────────────────────────────────
log ""
log "============================================="
if $FIX; then
log "SCAN + FIX COMPLETE"
log "  Mechanical fixes applied : $FIXED"
log "  Items still needing AI   : $FOUND"
else
log "SCAN COMPLETE"
log "  Items needing attention  : $FOUND"
fi
log "============================================="
log ""
log "Next steps:"
log ""
if $FIX && [[ $FOUND -gt 0 ]]; then
log "  Mechanical fixes have been applied. Review with: git diff"
log "  Then run migrate.sh to let AI handle the remaining [FOUND] items."
elif [[ $FOUND -gt 0 ]]; then
log "  IDE tools (Claude Code, Cursor, Copilot):"
log "    Run migrate.sh to apply fixes automatically."
log "    Or re-run with --fix to apply mechanical fixes first:"
log "      bash scan.sh --fix && bash migrate.sh"
log ""
log "  Chat tools (ChatGPT, Gemini, Claude.ai):"
log "    Paste migrate.log and docs/migration-guide.md into your chat, then:"
log '    "Read migrate.log for items needing fixes. Read migration-guide.md'
log '     for guidance. Apply fixes for every [FOUND] item, one at a time."'
else
log "  No items found — migration looks complete."
log "  Run on a real device at each API level to verify behavioural changes."
fi

echo ""
echo "Scan complete. $FIXED fixed, $FOUND remaining. See migrate.log for details."
