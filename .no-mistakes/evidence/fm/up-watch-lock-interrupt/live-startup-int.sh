#!/usr/bin/env bash
# live-startup-int.sh <firstmate-root> <runs> <mode>
# Drives the real bin/fm-watch.sh in a disposable lab FM_HOME. mode=pid: send
# SIGINT the instant the watcher's pid appears in state/.watch.lock/pid.
# mode=delay: send SIGINT after a random 0-400ms delay from launch.
# Then reports whether the lock was stranded and whether a fresh watcher can arm.
ROOT=$1 RUNS=$2 MODE=$3
WT=/Users/m.koval/.no-mistakes/worktrees/5447c8da5417/01M5ZGKEN8J3NP456VNZZZ21MG
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux"
ENVV=(env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u TMUX TMUX_TMPDIR="$LAB/tmux" FM_HOME="$LAB" FM_POLL=5 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999)
stranded=0 released=0 nolock=0
for r in $(seq 1 "$RUNS"); do
  rm -rf "$LAB/state/.watch.lock" "$LAB/state/.watcher-down"
  set -m
  "${ENVV[@]}" "$ROOT/bin/fm-watch.sh" >"$LAB/watch.$r.out" 2>&1 &
  pid=$!
  set +m
  if [ "$MODE" = pid ]; then
    i=0; while [ $i -lt 3000 ] && [ "$(cat "$LAB/state/.watch.lock/pid" 2>/dev/null)" != "$pid" ]; do i=$((i+1)); done
  else
    sleep "0.$(printf '%03d' $((RANDOM % 400)))"
  fi
  kill -INT "$pid" 2>/dev/null
  for _ in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
  kill -0 "$pid" 2>/dev/null && { kill -TERM "$pid"; sleep 0.5; }
  wait "$pid" 2>/dev/null; st=$?
  if [ -e "$LAB/state/.watch.lock/pid" ]; then
    holder=$(cat "$LAB/state/.watch.lock/pid"); stranded=$((stranded+1))
    echo "run $r: exit=$st STRANDED lock pid=$holder (alive: $(kill -0 "$holder" 2>/dev/null && echo yes || echo no)) down-marker=$([ -e "$LAB/state/.watcher-down" ] && echo yes || echo no)"
  elif [ -e "$LAB/state/.watcher-down" ]; then
    released=$((released+1)); echo "run $r: exit=$st lock released, downtime marker published"
  else
    nolock=$((nolock+1)); echo "run $r: exit=$st no lock, no marker (INT before acquisition)"
  fi
done
echo "SUMMARY root=$ROOT mode=$MODE runs=$RUNS stranded=$stranded released=$released pre-acquire=$nolock"
# Takeover: a fresh watcher must arm on whatever state the last run left.
"${ENVV[@]}" "$ROOT/bin/fm-watch.sh" >"$LAB/takeover.out" 2>&1 &
tp=$!
for _ in $(seq 1 100); do [ "$(cat "$LAB/state/.watch.lock/pid" 2>/dev/null)" = "$tp" ] && break; sleep 0.1; done
echo "TAKEOVER: lock pid=$(cat "$LAB/state/.watch.lock/pid" 2>/dev/null) fresh watcher pid=$tp; watcher output: $(head -c 300 "$LAB/takeover.out" | tr '\n' ' ')"
kill -TERM "$tp" 2>/dev/null; wait "$tp" 2>/dev/null
echo "after TERM of fresh watcher: lock present=$([ -e "$LAB/state/.watch.lock" ] && echo yes || echo no)"
rm -rf "$LAB"
