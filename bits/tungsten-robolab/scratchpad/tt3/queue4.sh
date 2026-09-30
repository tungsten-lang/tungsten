#!/bin/bash
# queue 4 (agent T3): the LITERAL ideal arm (reached = asked, absolute) and the mean-response ideal arm limited to muscle-like torques. After queue 3.
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
until grep -q "QUEUE3b DONE" out/tt3/run_oracle.progress; do sleep 3; done
run() { TT3_CFG="$1" scratchpad/tt3/run_oracle.sh "$2" "$3" "$4"; }
run '{"o2_abs":1}' o2abs o2 "A B"
run '{"o2_taumax":60}' o2cap o2 "A B"
echo "$(date '+%F %T') QUEUE4 DONE" >> out/tt3/run_oracle.progress
