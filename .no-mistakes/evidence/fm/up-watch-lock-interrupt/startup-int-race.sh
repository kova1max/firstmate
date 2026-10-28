#!/usr/bin/env bash
# Usage: startup-int-race.sh <repo-root> <runs>
# Launches the real bin/fm-watch.sh against a disposable lab home, sends SIGINT the
# instant the watch lock pid appears (no test seam), and reports whether the lock
# survived under a dead pid. Then checks whether a fresh watcher can arm.
ROOT=$1; RUNS=${2:-20}
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
stranded=0
for run in $(seq 1 "$RUNS"); do
  rm -rf "$LAB/state/.watch.lock"
  set -m
  env -u NO_MISTAKES_GATE -u FM_STATE_OVERRIDE FM_HOME="$LAB" FM_POLL=5 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 \
    "$ROOT/bin/fm-watch.sh" >"$LAB/watch.$run.out" 2>&1 &
  pid=$!
  set +m
  deadline=$((SECONDS+30))
  while [ $SECONDS -lt $deadline ] && [ "$(cat "$LAB/state/.watch.lock/pid" 2>/dev/null)" != "$pid" ]; do :; done
  kill -INT "$pid" 2>/dev/null
  wait "$pid"; st=$?
  if [ -e "$LAB/state/.watch.lock/pid" ]; then
    stranded=$((stranded+1)); echo "run $run: exit=$st lock STRANDED pid=$(cat "$LAB/state/.watch.lock/pid")"
  else
    echo "run $run: exit=$st lock released"
  fi
done
echo "SUMMARY root=$ROOT runs=$RUNS stranded=$stranded"
echo "--- follow-up arm after the last run (fm-watch-checkpoint --seconds 3):"
env -u NO_MISTAKES_GATE FM_HOME="$LAB" FM_POLL=1 FM_CHECK_INTERVAL=999999 "$ROOT/bin/fm-watch-checkpoint.sh" --seconds 3; echo "checkpoint exit=$?"
ls -la "$LAB/state/.watch.lock" 2>&1 | head -3
rm -rf "$LAB"
