#!/bin/zsh
# every stage's controller on the untouched validation seeds 6000-6047 (athlete body), as run
cd /Users/erik/tungsten/bits/tungsten-robolab
W=${1:-2}
run() { name=$1; p=$2; c=$3
  printf "%-12s " $name
  BAT_BODY=athlete .venv/bin/python playground/bat_rep.py eval --params $p --controller $c --seeds 6000:6048 --seconds 4.6 --workers $W --name stage_${name}_6000 --quiet | head -1
}
run v6knots params/bat_v6_knots.txt bin/challengers/bat_v6-knots1
run taim1 params/bat_r2_taim1.txt bin/challengers/bat_r2-t1
run s1 params/bat_r2_s1.txt bin/challengers/bat_r2-t1
run s2b params/bat_r2_s2b_g5.txt bin/challengers/bat_r2-t5
run s2c params/bat_r2_s2c.txt bin/challengers/bat_r2-t5
