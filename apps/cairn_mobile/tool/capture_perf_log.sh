#!/usr/bin/env bash
#
# capture_perf_log.sh
# Captures flutter_gemma native [*/perf] and Cairn [Cairn/perf] timing logs
# from a connected Android device via adb logcat.
#
# Filter pattern '/perf' captures all relevant sources:
#   [LiteRtLmFfi/perf]              — dylib load, settings_create, engine_create
#   [FfiInferenceModel/perf]        — createConversation, createSession total
#   [FfiInferenceModelSession/perf] — time-to-first-chunk (prefill), generation total
#   [Cairn/perf]                    — install, engine_create, generate (Dart layer)
#
# All of these appear under the 'flutter' logcat tag because flutter_gemma 0.14.3+
# and Cairn's PerfLogger both use debugPrint().
#
# Usage:
#   bash tool/capture_perf_log.sh [device_id] [duration_seconds]
#
# Examples:
#   bash tool/capture_perf_log.sh                          # default device, 300s
#   bash tool/capture_perf_log.sh RZCX920ARVA 120          # explicit device, 120s
#   bash tool/capture_perf_log.sh RZCX920ARVA 0            # indefinite (Ctrl+C)
#
# Output: perf_<timestamp>.txt in the current directory.
# Requires: adb (Android Platform Tools) in PATH.
# Reference: docs/optimization-plan.md §MEASURE-1, §Sprint-1

set -euo pipefail

DEVICE="${1:-RZCX920ARVA}"
DURATION="${2:-300}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTFILE="perf_${TIMESTAMP}.txt"

echo "[capture_perf_log] Device  : ${DEVICE}"
echo "[capture_perf_log] Duration: ${DURATION}s (0 = indefinite, Ctrl+C to stop)"
echo "[capture_perf_log] Output  : ${OUTFILE}"
echo "[capture_perf_log] Filter  : /perf  (flutter_gemma native + Cairn)"
echo "----"

if ! command -v adb &>/dev/null; then
    echo "ERROR: adb not found in PATH. Install Android Platform Tools." >&2
    exit 1
fi

cat > "${OUTFILE}" << EOF
# Cairn perf log — captured $(date '+%Y-%m-%d %H:%M:%S')
# Device  : ${DEVICE}
# Filter  : adb logcat | grep /perf
# Sources : [LiteRtLmFfi/perf]  [FfiInferenceModel/perf]
#           [FfiInferenceModelSession/perf]  [Cairn/perf]
# flutter_gemma: 0.14.3+
# Reference: docs/optimization-plan.md §MEASURE-1, §Sprint-1

EOF

# Clear the existing logcat buffer.
adb -s "${DEVICE}" logcat -c 2>/dev/null || true

echo "[capture_perf_log] Listening ... (Ctrl+C to stop early)"

if [[ "${DURATION}" -gt 0 ]]; then
    timeout "${DURATION}" \
        adb -s "${DEVICE}" logcat -v time 2>/dev/null \
        | grep --line-buffered '/perf' \
        | tee -a "${OUTFILE}" \
        || true
else
    adb -s "${DEVICE}" logcat -v time 2>/dev/null \
        | grep --line-buffered '/perf' \
        | tee -a "${OUTFILE}"
fi

echo "----"
LINES=$(grep -c '/perf' "${OUTFILE}" 2>/dev/null || echo 0)
echo "[capture_perf_log] Done. ${LINES} /perf line(s) captured to: ${OUTFILE}"
