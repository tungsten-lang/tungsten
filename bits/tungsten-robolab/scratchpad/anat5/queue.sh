#!/bin/bash
# queue.sh JOBFILE  -- run ES jobs one after another (one search at a time). Each JOBFILE line: ARM SEED BUDGET GEAR INIT SNAP [TAG]
# waits first for any running hsearch of this campaign (pid files es_*.pid alive), then launches each job with scratchpad/anat5/es5.sh and waits for its pid.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
alive() { for f in scratchpad/anat5/es_*.pid; do [ -f "$f" ] && kill -0 "$(cat $f)" 2>/dev/null && return 0; done; return 1; }
while alive; do sleep 20; done
while read -r ARM SEED BUDGET GEAR INIT SNAP TAG; do
  [ -z "$ARM" ] && continue
  case "$ARM" in \#*) continue;; esac
  while alive; do sleep 20; done
  echo "$(date '+%H:%M:%S') launching $ARM s$SEED gear $GEAR budget $BUDGET" >> scratchpad/anat5/queue.log
  GEAR=$GEAR scratchpad/anat5/es5.sh $ARM $SEED $BUDGET 3 $INIT $SNAP $TAG >> scratchpad/anat5/queue.log 2>&1
  sleep 5
  while alive; do sleep 20; done
  echo "$(date '+%H:%M:%S') finished $ARM s$SEED" >> scratchpad/anat5/queue.log
done < "$1"
echo "$(date '+%H:%M:%S') queue empty" >> scratchpad/anat5/queue.log
