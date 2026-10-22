#!/bin/zsh
# Edit demo: resolve a variant, show what will re-render (studio diff against the base), render only the missing
# segments (<= 400 frames per heavy-lock hold), mix (or reuse the cached mix), mux; time every step.
#   edit_demo.sh <studio dir> <variant name, e.g. edit_a> <log>
D=$1; V=$2; LOG=$3
L=~/math/tmp/ladder2/heavy.lock
G=~/math/openai/tools/guard.sh
S=${STUDIO_BIN:-$HOME/tungsten-worktrees/engine/apps/studio/bin/studio}
T=$HOME/tungsten-worktrees/engine/apps/studio/tools
ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
: > $LOG
t0=$(ms)
$S resolve $D/$V.json >> $LOG 2>&1
t1=$(ms); echo "step resolve_ms $((t1 - t0))" >> $LOG
$S diff $D/build/full/timeline.resolved.json $D/build/full/$V.timeline.resolved.json >> $LOG 2>&1
t2=$(ms)
$T/render_all.sh $D/$V.json 6 $LOG.render
t3=$(ms); echo "step render_ms_including_lock_waits $((t3 - t2))" >> $LOG
grep "render:" $LOG.render >> $LOG
out=$(lockf -k $L caffeinate -i /usr/bin/time -l $G 16384 1200 env TUNGSTEN_MEMORY_LIMIT=14G $S mix $D/$V.json 2>&1)
echo "$out" | grep -E "mix|[0-9] real|maximum resident" >> $LOG
out=$(lockf -k $L caffeinate -i /usr/bin/time -l $G 8192 1200 $S mux $D/$V.json 2>&1)
echo "$out" | grep -E "mux|[0-9] real|maximum resident|rror" >> $LOG
echo DONE >> $LOG
