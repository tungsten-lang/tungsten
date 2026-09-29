#!/bin/zsh
# The report's evaluation sets for one controller (batting round 2): validation 6000-6047 (untouched until now), the arena trial's seeds 1100-1123,
# the old fresh trial's seeds 1000-1023 and the 18-pitch grid; per-pitch tables in out/bat_r2/<name>_*.json.
#   scratchpad/bat/final_eval.sh NAME PARAMS CONTROLLER [WORKERS]      (ROBOLAB_PROFILE / BAT_* from the environment)
cd /Users/erik/tungsten/bits/tungsten-robolab
N=$1; P=$2; C=$3; W=${4:-4}
for set in "val6000 6000:6048" "arena1100 1100:1124" "oldfresh1000 1000:1024"; do
  n=${set% *}; s=${set#* }
  printf "%-14s " $n
  .venv/bin/python playground/bat_rep.py eval --params $P --controller $C --seeds $s --seconds 4.6 --workers $W --name ${N}_$n --quiet | head -1
done
printf "%-14s " grid18
BATREP_GRID=1 .venv/bin/python playground/bat_rep.py eval --params $P --controller $C --seeds 0:18 --seconds 4.6 --workers $W --name ${N}_grid --quiet | head -1
