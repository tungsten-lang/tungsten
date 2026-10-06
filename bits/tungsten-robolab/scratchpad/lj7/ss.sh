#!/bin/sh
# L7: one steering-scan variant: stepscan.py on a seed range with overrides, summary line appended to out/lj7/ss_summary.txt
# usage: ss.sh <name> <seeds> "<k=v,k=v>" [workers] [params] [controller]
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/lj7/env7.sh
name=$1; seeds=$2; over=$3; w=${4:-6}
params=${5:-scratchpad/lj6/params/runner_H011_SB2.txt}
ctl=${6:-bin/challengers/long_jump_run_y-l6a}
rm -f out/lj7/ss_${name}.done
nice -n 10 .venv/bin/python scratchpad/lj7/stepscan.py $params $ctl $seeds out/lj7/ss_${name}.json "$over" $w > out/lj7/ss_${name}.txt 2>&1
echo "$name [$seeds] [$over] :: $(tail -1 out/lj7/ss_${name}.txt)" >> out/lj7/ss_summary.txt
echo done > out/lj7/ss_${name}.done
