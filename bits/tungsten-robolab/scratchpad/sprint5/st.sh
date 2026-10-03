#!/bin/sh
# st.sh NAME INIT WORKERS MARGIN [rses.py args...]  -- START search (gear-1 tunables, standing starts, 10 s) of the labelled beyond-human sprinter; background, pid in out/sprint5/NAME.pid
cd /Users/erik/tungsten/bits/tungsten-robolab || exit 1
NAME=$1; INIT=$2; W=$3; M=$4; shift 4
EXCL="g2_*,g3_*,g4_*,g5_*,g6_*,g7_*,g8_*,g9_*,v_top,v_cap,k_sp,k_spd,fall_lean,fall_ankle,fall_place"
nohup nice -n 10 .venv/bin/python -u scratchpad/sprint5/rses.py $NAME $INIT --exclude "$EXCL" --pool 15001-15999 --k 48 --k2 64 --lam 10 --seconds 10 \
  --attrs objective=3,fall_pen=300 --margin $M --check 14001-14128 --check-every 4 --workers $W "$@" > out/sprint5/$NAME.out 2>&1 &
echo $! > out/sprint5/$NAME.pid
echo "started $NAME pid $(cat out/sprint5/$NAME.pid)"
