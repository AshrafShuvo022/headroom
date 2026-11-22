#!/bin/bash
# The standard 10-minute Android session, sampled every 60 s, then Home and TRIM_MEMORY_COMPLETE.
#
#   scripts/run-session.sh <package> [serial] > run.csv
#
# Cold-launches the app, prints a header with the phone and build, then a CSV row 20 s after
# launch, at the end of each minute, 8 s after the Home button, and 15 s after the trim.
# Tell the tester each minute's step on a clock (see reference.md); the launch is minute 0.
set -u
PKG=${1:?package name}; SERIAL=${2:-}
ADB="adb${SERIAL:+ -s $SERIAL}"
HERE=$(cd "$(dirname "$0")" && pwd)
export BASELINE_PIDS=${BASELINE_PIDS:-/tmp/headroom-baseline-pids.txt}

$ADB shell am force-stop "$PKG"; sleep 2
# WebView renderers already running belong to other apps: remember them so they are not counted.
$ADB shell dumpsys meminfo | awk '/^Total PSS by process:/{on=1;next} on&&/^Total PSS by/{exit}
  on && /sandboxed_process/ && /webview/ && match($0,/pid [0-9]+/) {print substr($0,RSTART+4,RLENGTH-4)}' > "$BASELINE_PIDS"

echo "# headroom session, $(date -u +%Y-%m-%dT%H:%MZ)"
echo "# device: $($ADB shell getprop ro.product.model | tr -d '\r'), Android $($ADB shell getprop ro.build.version.release | tr -d '\r')"
echo "# build : $($ADB shell dumpsys package "$PKG" | grep -m1 versionName | tr -d '\r' | sed 's/^ *//')"
echo "# method: cold launch; sample at +20 s, then every 60 s for 10 min; Home + 8 s; TRIM_MEMORY_COMPLETE + 15 s. Values KB."
echo "elapsed_s,label,pss_kb,rss_kb,native_kb,graphics_kb,java_kb,webviews,renderers,renderers_pss_kb"

T0=$(date +%s)
$ADB shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
while [ $(date +%s) -lt $((T0+20)) ]; do sleep 1; done
"$HERE/meminfo-sample.sh" "$PKG" "$SERIAL" launch+20 "$T0"
for i in $(seq 1 10); do
  while [ $(date +%s) -lt $((T0+i*60)) ]; do sleep 1; done
  "$HERE/meminfo-sample.sh" "$PKG" "$SERIAL" "min$((i-1))-end" "$T0"
done
$ADB shell input keyevent KEYCODE_HOME; sleep 8
"$HERE/meminfo-sample.sh" "$PKG" "$SERIAL" background "$T0"
$ADB shell am send-trim-memory "$PKG" COMPLETE; sleep 15
"$HERE/meminfo-sample.sh" "$PKG" "$SERIAL" after-trim "$T0"
