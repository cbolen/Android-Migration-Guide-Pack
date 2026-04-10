#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# scan.sh — Android migration pattern scanner
#
# Scans the project for patterns requiring migration to Android 15 (API 35).
# Makes NO changes — findings written to migrate.log.
#
# Works with any AI tool:
#   - Claude Code / Cursor / Copilot: run scan.sh, then run migrate.sh
#   - ChatGPT / Gemini / Claude.ai:  run scan.sh, paste migrate.log into chat
#
# Usage:
#   bash scan.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOG="$ROOT/migrate.log"
: > "$LOG"
FOUND=0

log()   { echo "$*" | tee -a "$LOG"; }
found() { FOUND=$((FOUND+1)); log "  [FOUND]  $*"; }
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

# ── Auto-detect project layout ────────────────────────────────────────────────
APP_BUILD=$(find "$ROOT" -maxdepth 2 -name "build.gradle" -path "*/app/*" | head -1)
MANIFEST=$(find "$ROOT" -path "*/src/main/AndroidManifest.xml" | head -1)

[[ -z "$APP_BUILD" ]] && { echo "ERROR: app/build.gradle not found"; exit 1; }
[[ -z "$MANIFEST" ]]  && { echo "ERROR: AndroidManifest.xml not found"; exit 1; }

CURRENT_TARGET=$(grep 'targetSdk' "$APP_BUILD" 2>/dev/null | sed 's/[^0-9]//g' | head -1)

log "============================================="
log "scan.sh — Android migration scanner"
log "Project   : $ROOT"
log "targetSdk : ${CURRENT_TARGET:-unknown}"
log "Scan date : $(date)"
log "============================================="
log ""

# ── Build config ──────────────────────────────────────────────────────────────
log "=== BUILD ==="
if [[ -n "$CURRENT_TARGET" && "$CURRENT_TARGET" -lt 35 ]]; then
  found "targetSdk $CURRENT_TARGET — needs to reach 35"
else
  ok "targetSdk 35"
fi

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
scan_src 'Handler\(\)' \
  "Handler() no-arg constructor — removed API 33, use Handler(Looper.getMainLooper())"
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
  "DataWedge receiver export flag set"
scan_src 'EMDKManager|EMDKResults|emdkManager' \
  "EMDK usage — verify EMDKManager released in onPause/onDestroy"

# ── Summary ───────────────────────────────────────────────────────────────────
log ""
log "============================================="
log "SCAN COMPLETE — $FOUND item(s) need attention"
log "============================================="
log ""
log "Next steps:"
log ""
log "  IDE tools (Claude Code, Cursor, Copilot):"
log "    Run migrate.sh to apply fixes automatically."
log ""
log "  Chat tools (ChatGPT, Gemini, Claude.ai):"
log "    Paste the contents of this file (migrate.log) into your chat,"
log "    along with docs/migration-guide.md, then send this prompt:"
log ""
log '    "Read migrate.log for the list of items needing fixes.'
log '     Read migration-guide.md for guidance and Kotlin examples.'
log '     Apply fixes for every [FOUND] item, one at a time."'

echo ""
echo "Scan complete. $FOUND item(s) found. See migrate.log for details."
