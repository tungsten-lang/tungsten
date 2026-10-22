#!/bin/zsh
# Render every missing segment of an episode, at most 400 frames per heavy-lock hold (house rule), each hold under
# the memory guard and /usr/bin/time; appends one block per hold to LOG and stops when nothing is missing.
#   apps/studio/tools/render_all.sh <episode.json> [jobs] [log]
E=$1; J=${2:-6}; LOG=${3:-render_all.log}
L=~/math/tmp/ladder2/heavy.lock
G=~/math/openai/tools/guard.sh
S=${STUDIO_BIN:-$HOME/tungsten-worktrees/engine/apps/studio/bin/studio}
while true; do
  out=$(lockf -k $L caffeinate -i /usr/bin/time -l $G 16384 1200 $S render $E --jobs $J --max-frames 400 2>&1)
  echo "$out" | grep -E "render:|program|[0-9] real|maximum resident|peak memory|rror|failed|guard:" >> $LOG
  echo "$out" | grep -q "nothing to do" && break
  if ! echo "$out" | grep -qE "render: [0-9]+ frames"; then echo "FAILED" >> $LOG; echo "$out" | tail -20 >> $LOG; break; fi
done
echo DONE >> $LOG
