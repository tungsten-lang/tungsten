#!/bin/sh
# Ideal-control ("sweet") ceilings through a practised swing's own contact point (batting round 2): bat_ceiling.py --target sweet
# (open loop, reflex off, 16 upper-body joints, CMA over a net excitation every 40 ms, ball moved out of the way; the score is the sweet-spot
# speed at its closest approach to where the practised swing met the ball, contact time free) on the centre pitch (34.0 m/s, x 0.0, z 0.80),
# captured 20 ms before the hips fire from a robolab-representation swing.
#   scratchpad/bat/ceil_sweet.sh GENS variant ...     (one at a time, 4 workers; results out/bat_ceiling/r2sw_<variant>.json)
cd /Users/erik/tungsten/bits/tungsten-robolab
G=$1; shift
run() {  # name, "ENV=.. ENV=..", params, controller
  name=$1; envs=$2; params=$3; ctl=$4
  echo "== $name: $envs $params $ctl ($(date +%H:%M:%S))"
  env $envs .venv/bin/python playground/bat_ceiling.py --params $params --controller $ctl --pitch 34.0,0.0,0.8 --target sweet \
      --gens $G --workers 4 --name r2sw_$name 2>&1 | grep -E "practised|gen (0|50|100|150|200|250|299) |saved"
}
for v in "$@"; do
  case $v in
    s3)      run s3      "BAT_BODY=athlete" params/bat_r2_s3.txt bin/challengers/bat_r2-t8 ;;
    p95)     run p95     "BAT_BODY=athlete ROBOLAB_PROFILE=p95" params/bat_r2_p95_s8.txt bin/challengers/bat_r2-t8 ;;
    s3p95)   run s3p95   "BAT_BODY=athlete ROBOLAB_PROFILE=p95" params/bat_r2_s3.txt bin/challengers/bat_r2-t8 ;;
    str133)  run str133  "BAT_BODY=athlete BAT_STRENGTH=2.0" params/bat_r2_s3.txt bin/challengers/bat_r2-t8 ;;
    *) echo "unknown variant $v" ;;
  esac
done
