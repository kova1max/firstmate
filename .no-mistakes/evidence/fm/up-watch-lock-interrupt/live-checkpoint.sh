#!/usr/bin/env bash
# live-checkpoint.sh <firstmate-root> <runs>: run the real bin/fm-watch-checkpoint.sh
# with a 1s bound (so its INT can land in the watcher's startup window) in a lab
# FM_HOME, then report whether the watch lock survived and whether a fresh
# checkpoint can take over (not "watcher: already running").
ROOT=$1 RUNS=$2
WT=/Users/m.koval/.no-mistakes/worktrees/5447c8da5417/01M5ZGKEN8J3NP456VNZZZ21MG
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux"
ENVV=(env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u TMUX TMUX_TMPDIR="$LAB/tmux" FM_HOME="$LAB" FM_POLL=1 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999)
left=0
for r in $(seq 1 "$RUNS"); do
  "${ENVV[@]}" "$ROOT/bin/fm-watch-checkpoint.sh" --seconds 1 >"$LAB/ck.$r.out" 2>&1; st=$?
  if [ -e "$LAB/state/.watch.lock/pid" ]; then
    h=$(cat "$LAB/state/.watch.lock/pid"); left=$((left+1))
    echo "run $r: checkpoint exit=$st LOCK LEFT pid=$h alive=$(kill -0 "$h" 2>/dev/null && echo yes || echo no) | $(tr '\n' ' ' < "$LAB/ck.$r.out")"
  else
    echo "run $r: checkpoint exit=$st lock gone | $(tr '\n' ' ' < "$LAB/ck.$r.out")"
  fi
done
echo "SUMMARY root=$ROOT runs=$RUNS lock-left=$left"
rm -rf "$LAB"
