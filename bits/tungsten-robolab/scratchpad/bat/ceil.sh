#!/bin/sh
# Ideal-control ceilings of changed bodies and of an earlier start (batting round 2): one bat_ceiling.py --ball CMA run per variant on the
# centre grid pitch (34.0 m/s, x 0.0, z 0.80: the location of out/bat_ceiling/ball_s0.json, 25.69 m/s), captured from a robolab-representation swing.
#   scratchpad/bat/ceil.sh PARAMS CONTROLLER GENS [variant ...]
# Runs one at a time (2 workers); results out/bat_ceiling/r2_<variant>.json (summary: scratchpad/bat/ceil_report.py).
cd /Users/erik/tungsten/bits/tungsten-robolab
P=$1; C=$2; G=${3:-300}; shift 3
run() {  # name, "ENV=.. ENV=..", extra bat_ceiling args
  name=$1; envs=$2; extra=$3
  echo "== $name: $envs $extra ($(date +%H:%M:%S))"
  env $envs .venv/bin/python playground/bat_ceiling.py --params $P --controller $C --pitch 34.0,0.0,0.8 --ball --gens $G --workers ${CEIL_WORKERS:-2} --name r2_$name $extra 2>&1 | grep -E "practised|gen (0|100|200|299) |saved"
}
for v in "$@"; do
  case $v in
    base)    run base    "BAT_BODY=athlete" "--lead 0" ;;
    str20)   run str20   "BAT_BODY=athlete BAT_STRENGTH=2.0" "--lead 0" ;;
    vmax45)  run vmax45  "BAT_BODY=athlete BAT_VMAX=4.5" "--lead 0" ;;
    trunk15) run trunk15 "BAT_BODY=athlete BAT_GROUP_STRENGTH=pelvis_yaw=1.5,spine_=1.5" "--lead 0" ;;
    arms15)  run arms15  "BAT_BODY=athlete BAT_GROUP_STRENGTH=l_shoulder=1.5,r_shoulder=1.5,l_elbow=1.5,r_elbow=1.5,l_wrist=1.5,r_wrist=1.5" "--lead 0" ;;
    lead5)   run lead5   "BAT_BODY=athlete" "--lead 0.05 --window 0.39" ;;
    lead10)  run lead10  "BAT_BODY=athlete" "--lead 0.10 --window 0.44" ;;
    prog_athlete) run prog_athlete "BAT_BODY=athlete" "--lead 0" ;;                        # with the ORACLE program capture (params/bat_v6_prog.txt): round 1's recipe
    prog_p95)     run prog_p95     "BAT_BODY=athlete ROBOLAB_PROFILE=p95" "--lead 0" ;;
    *) echo "unknown variant $v" ;;
  esac
done
