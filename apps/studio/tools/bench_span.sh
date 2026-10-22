#!/bin/zsh
# Render a frame span fresh (into a scratch segment directory, not the cache) in <= 400-frame lock holds and log
# /usr/bin/time per hold.   bench_span.sh <episode.json> <from> <to> <jobs> <encoder: videotoolbox|ffmpeg> <log>
E=$1; A=$2; B=$3; J=$4; ENC=$5; LOG=$6
EPDIR=$(cd "$(dirname $E)" && pwd)
SEG=$EPDIR/build/bench_segments_${ENC}_j${J}
rm -rf $SEG; mkdir -p $SEG
L=~/math/tmp/ladder2/heavy.lock
G=~/math/openai/tools/guard.sh
S=${STUDIO_BIN:-$HOME/tungsten-worktrees/engine/apps/studio/bin/studio}
: > $LOG
while true; do
  out=$(STUDIO_SEGMENTS=$SEG STUDIO_ENCODER=$ENC lockf -k $L caffeinate -i /usr/bin/time -l $G 16384 1200 $S render $E --from $A --to $B --jobs $J --max-frames 400 2>&1)
  echo "$out" | grep -E "render:|[0-9] real|maximum resident|peak memory|rror|failed|guard:" >> $LOG
  echo "$out" | grep -q "nothing to do" && break
  echo "$out" | grep -qE "render: [0-9]+ frames" || { echo FAILED >> $LOG; echo "$out" | tail >> $LOG; break; }
done
du -sk $SEG | awk '{print "segments_kb " $1}' >> $LOG
echo DONE >> $LOG
