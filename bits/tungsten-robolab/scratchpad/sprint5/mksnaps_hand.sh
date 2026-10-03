#!/bin/sh
# mksnaps_hand.sh CHAIN CTL TAG WORKERS -- gear-1 snapshots for the HANDOVER (gear-2) search: one real right touchdown per run at 6.9-7.4 m/s (before the switch at 7.6), t 3-14 s;
# selection set (14001-14256) -> playground/cache/sprint_touch_run_v4_h<TAG>s.npz, training set (15001-15512) -> ..._h<TAG>t.npz
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint4/env.sh
CH=$1; CTL=$2; TAG=$3; W=${4:-2}
nice -n 10 .venv/bin/python scratchpad/sprint4/snap3.py $CH $CTL playground/cache/sprint_touch_run_v4_h${TAG}s.npz --seeds 14001-14256 --secs 14 --t0 3 --t1 14 --vmin 6.9 --vmax 7.4 --workers $W > out/sprint5/snap_h${TAG}s.log 2>&1
nice -n 10 .venv/bin/python scratchpad/sprint4/snap3.py $CH $CTL playground/cache/sprint_touch_run_v4_h${TAG}t.npz --seeds 15001-15512 --secs 14 --t0 3 --t1 14 --vmin 6.9 --vmax 7.4 --workers $W > out/sprint5/snap_h${TAG}t.log 2>&1
echo "==> Done snaps" >> out/sprint5/snap_h${TAG}t.log
