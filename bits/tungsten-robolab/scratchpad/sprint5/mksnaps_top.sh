#!/bin/sh
# top-gear snapshot sets of chain D (before the gear-3 switch: v 9.0-9.3, a real right touchdown, t 10-28 s): training (15001-15512) and selection (14001-14256)
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
. scratchpad/sprint4/env.sh
W=${1:-2}
nice -n 10 .venv/bin/python scratchpad/sprint4/snap3.py params/run_gearx_v4_beyond_d.txt bin/challengers/run_gearx-s4b playground/cache/sprint_touch_run_v4_s5s.npz --seeds 14001-14256 --secs 30 --t0 10 --t1 28 --vmin 9.0 --vmax 9.3 --workers $W > out/sprint5/snap_s5s.log 2>&1
nice -n 10 .venv/bin/python scratchpad/sprint4/snap3.py params/run_gearx_v4_beyond_d.txt bin/challengers/run_gearx-s4b playground/cache/sprint_touch_run_v4_s5t.npz --seeds 15001-15512 --secs 30 --t0 10 --t1 28 --vmin 9.0 --vmax 9.3 --workers $W > out/sprint5/snap_s5t.log 2>&1
echo "==> Done snaps" >> out/sprint5/snap_s5t.log
