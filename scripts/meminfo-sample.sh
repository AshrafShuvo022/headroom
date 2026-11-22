#!/bin/bash
# One Android memory sample as a CSV row.
#
#   scripts/meminfo-sample.sh <package> [serial] [label] [t0-epoch]
#
# Columns: elapsed_s,label,pss_kb,rss_kb,native_kb,graphics_kb,java_kb,webviews,renderers,renderers_pss_kb
# "renderers" are the app's WebView renderer processes (Chrome's sandboxed_process) that were
# not already running when BASELINE_PIDS was written (see run-session.sh); without that file,
# every WebView renderer on the phone is counted.
set -u
PKG=${1:?package name}; SERIAL=${2:-}; LABEL=${3:-sample}; T0=${4:-$(date +%s)}
ADB="adb${SERIAL:+ -s $SERIAL}"
BASE=${BASELINE_PIDS:-/tmp/headroom-baseline-pids.txt}
EL=$(( $(date +%s) - T0 ))
M=$($ADB shell dumpsys meminfo "$PKG")
pick() { echo "$M" | awk -v k="$1" 'index($0,k) {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/){print $i; exit}}'; }
PSS=$(echo "$M" | awk '/TOTAL PSS:/{print $3; exit}')
RSS=$(echo "$M" | awk '{for(i=1;i<NF;i++) if($i=="RSS:" && $(i-1)=="TOTAL") {print $(i+1); exit}}')
NAT=$(pick "Native Heap:"); GFX=$(pick "Graphics:"); JAVA=$(pick "Java Heap:")
WV=$(echo "$M" | awk '{for(i=1;i<=NF;i++) if($i=="WebViews:") {print $(i+1); exit}}')
R=$($ADB shell dumpsys meminfo | awk '/^Total PSS by process:/{on=1;next} on&&/^Total PSS by/{exit}
  on && /sandboxed_process/ && /webview/ {kb=$1; gsub(/[,K:]/,"",kb); if (match($0,/pid [0-9]+/)) print substr($0,RSTART+4,RLENGTH-4), kb}')
if [ -f "$BASE" ]; then R=$(echo "$R" | while read -r p kb; do [ -n "$p" ] && ! grep -qx "$p" "$BASE" && echo "$p $kb"; done); fi
RN=$(echo "$R" | grep -c .); RK=$(echo "$R" | awk '{s+=$2} END{print s+0}')
echo "$EL,$LABEL,$PSS,$RSS,$NAT,$GFX,$JAVA,$WV,$RN,$RK"
