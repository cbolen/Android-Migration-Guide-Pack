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
VERIFY=0

log()    { echo "$*" | tee -a "$LOG"; }
found()  { FOUND=$((FOUND+1));  log "  [FOUND]  $*"; }
verify() { VERIFY=$((VERIFY+1)); log "  [VERIFY] $*"; }
fixed()  { FIXED=$((FIXED+1));  log "  [FIXED]  $*"; }
ok()     { log "  [OK]     $*"; }

# [FOUND] — genuine issue requiring a fix
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

# [VERIFY] — pattern found, may already be correctly implemented; confirm manually
scan_src_verify() {
  local pattern="$1" msg="$2"
  local hits
  hits=$(grep -rn --include='*.java' --include='*.kt' -E "$pattern" "$ROOT/app/src" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    verify "$msg"
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

# [VERIFY] — manifest pattern found, may already be correctly handled; confirm manually
scan_manifest_verify() {
  local pattern="$1" msg="$2"
  [[ ! -f "$MANIFEST" ]] && { log "  [SKIP]   $msg (manifest not found)"; return; }
  local hits
  hits=$(grep -n -E "$pattern" "$MANIFEST" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    verify "$msg"
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
scan_manifest_verify 'intent-filter' \
  "Components with intent-filter — confirm android:exported is set on each (install failure if missing)"
scan_src_verify 'PendingIntent\.(getActivity|getBroadcast|getService|getForegroundService)' \
  "PendingIntent calls — confirm FLAG_IMMUTABLE or FLAG_MUTABLE on every call (runtime crash if missing)"
scan_src 'Cipher\.getInstance.*"BC"' \
  "BouncyCastle provider — removed API 31, use default provider"

# Notification trampoline: BroadcastReceiver subclass that calls startActivity()
_receiver_files=$(grep -rln --include='*.java' --include='*.kt' -E ':\s*BroadcastReceiver|extends BroadcastReceiver' "$ROOT/app/src" 2>/dev/null || true)
_trampoline_files=""
if [[ -n "$_receiver_files" ]]; then
  while IFS= read -r _f; do
    grep -qE 'startActivity\(' "$_f" 2>/dev/null && _trampoline_files="${_trampoline_files}${_f}\n"
  done <<< "$_receiver_files"
fi
if [[ -n "$_trampoline_files" ]]; then
  found "Notification trampoline — BroadcastReceiver calls startActivity() (blocked API 31+; attach PendingIntent directly to notification)"
  printf '%b' "$_trampoline_files" | while IFS= read -r _f; do [[ -n "$_f" ]] && log "             $_f"; done
else
  ok "Notification trampoline — no BroadcastReceiver calls startActivity()"
fi

# Exact alarm: [FOUND] if code uses it but permission is missing; [VERIFY] if permission is present
_exact_hits=$(grep -rn --include='*.java' --include='*.kt' -E 'setExactAndAllowWhileIdle|setAlarmClock|\.setExact\(' "$ROOT/app/src" 2>/dev/null || true)
if [[ -n "$_exact_hits" ]]; then
  if [[ -f "$MANIFEST" ]] && ! grep -qE 'SCHEDULE_EXACT_ALARM|USE_EXACT_ALARM' "$MANIFEST" 2>/dev/null; then
    found "Exact alarm used but SCHEDULE_EXACT_ALARM missing from manifest (SecurityException on API 31+)"
    echo "$_exact_hits" | while IFS= read -r line; do log "             $line"; done
  else
    verify "Exact alarm — permission declared; confirm canScheduleExactAlarms() guard is in code"
    echo "$_exact_hits" | while IFS= read -r line; do log "             $line"; done
  fi
else
  ok "Exact alarm — no setExact* calls found"
fi
scan_src 'ACTION_CLOSE_SYSTEM_DIALOGS' \
  "ACTION_CLOSE_SYSTEM_DIALOGS — throws SecurityException on API 31+"
scan_src 'MediaRecorder\(\)' \
  "MediaRecorder() no-arg constructor — removed API 31, use MediaRecorder(context)"
scan_manifest 'android\.permission\.BLUETOOTH"|android\.permission\.BLUETOOTH_ADMIN"' \
  "Legacy Bluetooth permissions — replace BLUETOOTH/BLUETOOTH_ADMIN with BLUETOOTH_SCAN/BLUETOOTH_CONNECT/BLUETOOTH_ADVERTISE (API 31+)"

# Custom splash screen: activity with postDelayed/Thread.sleep + startActivity + finish() = timed splash pattern
# API 31+ enforces system splash screen before app launches; custom splash causes double-splash
_splash_files=$(grep -rln --include='*.kt' --include='*.java' -E 'postDelayed|Thread\.sleep' "$ROOT/app/src" 2>/dev/null || true)
_splash=""
if [[ -n "$_splash_files" ]]; then
  while IFS= read -r _f; do
    grep -qE 'startActivity\(' "$_f" 2>/dev/null && \
    grep -qE 'finish\(\)' "$_f" 2>/dev/null && \
    grep -qE 'AppCompatActivity|Activity' "$_f" 2>/dev/null && \
    _splash="$_f" && break
  done <<< "$_splash_files"
fi
if [[ -n "$_splash" ]]; then
  found "Custom splash screen — migrate to androidx.core:core-splashscreen (API 31+ shows system splash before app; causes double-splash)"
  log "             $_splash"
else
  ok "Custom splash screen — none found"
fi
scan_src_verify 'GCMParameterSpec|AES/GCM' \
  "AES/GCM cipher — confirm exactly 12-byte IV is used (any other length throws on API 31)"

# ── API 33 (Android 13) ───────────────────────────────────────────────────────
log ""
log "=== API 33 (Android 13) ==="
scan_src 'AsyncTask' \
  "AsyncTask — removed API 33, replace with coroutines or WorkManager"
scan_src_verify 'registerReceiver\(' \
  "registerReceiver() — confirm RECEIVER_NOT_EXPORTED or RECEIVER_EXPORTED flag is passed on API 33+"
scan_src 'BluetoothAdapter.*\.enable\(\)|BluetoothAdapter.*\.disable\(\)' \
  "BluetoothAdapter.enable/disable() — always returns false on API 33+, use ACTION_REQUEST_ENABLE"
scan_src 'getParcelableExtra\("[^"]*"\)' \
  "getParcelableExtra(key) untyped — use getParcelableExtra(key, Class) on API 33+"
scan_src 'getSerializableExtra\("[^"]*"\)' \
  "getSerializableExtra(key) untyped — use getSerializableExtra(key, Class) on API 33+"
# POST_NOTIFICATIONS: [FOUND] if NotificationManager is used but permission is missing
_notify_files=$(grep -rln --include='*.java' --include='*.kt' -E 'NotificationManager' "$ROOT/app/src" 2>/dev/null || true)
if [[ -n "$_notify_files" ]]; then
  if [[ -f "$MANIFEST" ]] && ! grep -qE 'POST_NOTIFICATIONS' "$MANIFEST" 2>/dev/null; then
    found "Notifications used but POST_NOTIFICATIONS missing from manifest (silently dropped on API 33+)"
    echo "$_notify_files" | while IFS= read -r _f; do log "             $_f"; done
  else
    verify "POST_NOTIFICATIONS declared in manifest — confirm runtime permission request is in code"
    grep -n 'POST_NOTIFICATIONS' "$MANIFEST" 2>/dev/null | while IFS= read -r line; do log "             AndroidManifest.xml:$line"; done
  fi
else
  ok "POST_NOTIFICATIONS — no NotificationManager usage found"
fi
scan_manifest_verify 'READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE' \
  "Legacy storage permissions — confirm guarded with maxSdkVersion or replaced with READ_MEDIA_* on API 33+"
scan_manifest 'android:sharedUserId' \
  "android:sharedUserId — deprecated API 33; add android:sharedUserMaxSdkVersion=\"32\" and plan migration to FileProvider/content providers"

# ── API 34 (Android 14) ───────────────────────────────────────────────────────
log ""
log "=== API 34 (Android 14) ==="
# foregroundServiceType: [FOUND] if startForeground() used but type absent from manifest (runtime crash API 34+)
_fg_hits=$(grep -rn --include='*.kt' --include='*.java' -E 'startForeground\(' "$ROOT/app/src" 2>/dev/null || true)
if [[ -n "$_fg_hits" ]]; then
  if [[ -f "$MANIFEST" ]] && ! grep -qE 'foregroundServiceType' "$MANIFEST" 2>/dev/null; then
    found "startForeground() used but foregroundServiceType missing from manifest (runtime crash on API 34+)"
    echo "$_fg_hits" | while IFS= read -r line; do log "             $line"; done
  else
    verify "foregroundServiceType declared — confirm type matches service usage"
    grep -n 'foregroundServiceType' "$MANIFEST" 2>/dev/null | while IFS= read -r line; do log "             AndroidManifest.xml:$line"; done
  fi
else
  ok "foregroundServiceType — no startForeground() calls found"
fi
scan_src_verify 'canScheduleExactAlarms' \
  "canScheduleExactAlarms() — confirm check is also present in onResume (auto-revoked on app update)"
scan_src_verify 'DexClassLoader|PathClassLoader|InMemoryDexClassLoader' \
  "Dynamic DEX loading — confirm file.setReadOnly() is called before loading on API 34+"
scan_src_verify 'ZipFile|ZipInputStream' \
  "ZipFile/ZipInputStream — confirm entry names are validated against path traversal on API 34+"
scan_manifest_verify 'USE_FULL_SCREEN_INTENT' \
  "USE_FULL_SCREEN_INTENT — confirm canUseFullScreenIntent() check with IMPORTANCE_HIGH fallback"

# ── API 35 (Android 15) ───────────────────────────────────────────────────────
log ""
log "=== API 35 (Android 15) ==="
scan_src 'override fun onBackPressed|public void onBackPressed' \
  "onBackPressed() override — replace with OnBackPressedCallback (predictive back enforced)"
scan_src 'startActivityForResult|onActivityResult|onRequestPermissionsResult' \
  "Deprecated result APIs — replace with ActivityResultContracts"
scan_src_verify 'WindowInsetsCompat|setOnApplyWindowInsetsListener' \
  "Edge-to-edge inset handling present — confirm all activities are covered (enforced API 35)"
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
scan_manifest_verify 'MANAGE_EXTERNAL_STORAGE' \
  "MANAGE_EXTERNAL_STORAGE — evaluate whether scoped storage APIs can replace this"

# ── Zebra-specific ────────────────────────────────────────────────────────────
log ""
log "=== ZEBRA-SPECIFIC ==="
# DataWedge RECEIVER_NOT_EXPORTED: [FOUND] if DataWedge used with registerReceiver but flag absent
_dw_files=$(grep -rln --include='*.kt' --include='*.java' -E 'com\.symbol\.datawedge|DataWedge' "$ROOT/app/src" 2>/dev/null || true)
_dw_reg=$(grep -rln --include='*.kt' --include='*.java' -E 'registerReceiver' "$ROOT/app/src" 2>/dev/null || true)
if [[ -n "$_dw_files" ]] && [[ -n "$_dw_reg" ]]; then
  # Exclude comment-only lines so a TODO comment doesn't mask a missing flag
  _dw_flag=$(grep -rn --include='*.kt' --include='*.java' -E 'RECEIVER_NOT_EXPORTED|RECEIVER_EXPORTED' "$ROOT/app/src" 2>/dev/null | grep -vE ':\s*//' || true)
  if [[ -z "$_dw_flag" ]]; then
    found "DataWedge registerReceiver() missing RECEIVER_NOT_EXPORTED flag (SecurityException on API 33+)"
    echo "$_dw_reg" | while IFS= read -r _f; do log "             $_f"; done
  else
    verify "DataWedge receiver export flag present — confirm applied to all DataWedge registerReceiver() calls"
    echo "$_dw_flag" | while IFS= read -r line; do log "             $line"; done
  fi
else
  ok "DataWedge receiver — no DataWedge registerReceiver() usage found"
fi
scan_src_verify 'EMDKManager|EMDKResults|emdkManager' \
  "EMDK usage — confirm EMDKManager.release() is called in onPause/onDestroy"

# ── Summary ───────────────────────────────────────────────────────────────────
log ""
log "============================================="
if $FIX; then
log "SCAN + FIX COMPLETE"
log "  Mechanical fixes applied : $FIXED"
log "  [FOUND]  — genuine issues needing a fix : $FOUND"
log "  [VERIFY] — confirmed by scan, check manually: $VERIFY"
else
log "SCAN COMPLETE"
log "  [FOUND]  — genuine issues needing a fix : $FOUND"
log "  [VERIFY] — confirmed by scan, check manually: $VERIFY"
fi
log ""
log "  [FOUND]  items need code changes — run migrate.sh or fix manually."
log "  [VERIFY] items are pattern-detected and may already be correct;"
log "           review each one against the running app on a real device."
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
log "  No [FOUND] items — migration looks complete."
log "  Review any [VERIFY] items above and test on a real device at each API level."
fi

echo ""
echo "Scan complete. $FIXED fixed, $FOUND [FOUND], $VERIFY [VERIFY]. See migrate.log for details."
