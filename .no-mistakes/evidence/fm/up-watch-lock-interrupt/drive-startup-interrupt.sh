#!/usr/bin/env bash
# Live driver: start the real bin/fm-watch.sh in a disposable lab home, interrupt it
# during startup, and show the resulting lock state plus whether a new watcher can take over.
# Usage: drive-startup-interrupt.sh <bin-dir> <label> <mode: hang|race|steady|term>
set -u
BIN=$1; LABEL=$2; MODE=$3; WT=$(pwd)
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); bash "$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
ENV=(env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" FM_POLL=5 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999)
echo "== [$LABEL] mode=$MODE bin=$BIN"
set -m
case $MODE in
  hang|term) "${ENV[@]}" FM_WATCH_STARTUP_HANG=30 "$BIN/fm-watch.sh" >"$LAB/w1.out" 2>&1 & ;;
  *) "${ENV[@]}" "$BIN/fm-watch.sh" >"$LAB/w1.out" 2>&1 & ;;
esac
PID=$!; set +m
for i in $(seq 200); do [ -e "$LAB/state/.watch.lock/pid" ] && break; sleep 0.02; done
case $MODE in
  hang|term) for i in $(seq 200); do [ -e "$LAB/state/.watch-startup-hang" ] && break; sleep 0.05; done ;;
  steady) sleep 3 ;;
  race) sleep "${DELAY:-0}" ;;
esac
echo "lock pid before signal: $(cat "$LAB/state/.watch.lock/pid" 2>/dev/null) (watcher pid $PID)"
SIG=INT; [ "$MODE" = term ] && SIG=TERM
kill -$SIG $PID; echo "sent SIG$SIG"
for i in $(seq 200); do kill -0 $PID 2>/dev/null || break; sleep 0.05; done
if kill -0 $PID 2>/dev/null; then echo "WATCHER SURVIVED SIG$SIG (still running 10s later, holding lock)"; kill -TERM $PID; sleep 2; fi
wait $PID; echo "watcher exit status: $?"
if [ -e "$LAB/state/.watch.lock" ]; then
  H=$(cat "$LAB/state/.watch.lock/pid" 2>/dev/null); echo "lock dir REMAINS, holder pid=$H alive=$(kill -0 "$H" 2>/dev/null && echo yes || echo no)"
else echo "lock dir released"; fi
[ -e "$LAB/state/.watcher-down" ] && echo "downtime marker published: $(head -c 200 "$LAB/state/.watcher-down" | tr '\n' ' ')"
echo "-- watcher output:"; sed 's/^/   /' "$LAB/w1.out"
echo "-- successor arm (fm-watch.sh started fresh):"
set -m; "${ENV[@]}" "$BIN/fm-watch.sh" >"$LAB/w2.out" 2>&1 & P2=$!; set +m
for i in $(seq 100); do [ "$(cat "$LAB/state/.watch.lock/pid" 2>/dev/null)" = "$P2" ] && break; sleep 0.05; done
echo "successor pid=$P2 lock holder=$(cat "$LAB/state/.watch.lock/pid" 2>/dev/null) running=$(kill -0 $P2 2>/dev/null && echo yes || echo no)"
kill -INT $P2 2>/dev/null; wait $P2 2>/dev/null
echo "successor output:"; sed 's/^/   /' "$LAB/w2.out"
rm -rf "$LAB"
