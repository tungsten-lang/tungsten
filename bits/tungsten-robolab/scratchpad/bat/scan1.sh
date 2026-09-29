#!/bin/sh
# one-at-a-time probes around params/bat_r2_taim1.txt on the 16 maximin training pitches (batting round 2)
cd /Users/erik/tungsten/bits/tungsten-robolab
TR=3008,3049,3050,3060,3064,3073,3074,3091,3092,3102,3107,3108,3115,3118,3127,3138
for s in "" "step_delay=0.18" "step_delay=0.2" "hip_open=0.1" "hip_open=0.25" "prog_trig=0.21" "prog_trig=0.25" "train_end=-0.01" "train_end=0.015" "train_gain=0.8" "train_gain=1.3" "train_drv=0.8" "train_drv=1.2" "arm_swing_kd=0.03" "dur_arc=0.4" "dur_arc=0.5"; do
  name=scan1_$(echo "${s:-base}" | tr '=,' '__')
  .venv/bin/python playground/bat_rep.py eval --params params/bat_r2_taim1.txt --controller bin/challengers/bat_r2-t1 --seeds $TR --set "$s" --seconds 4.3 --workers 2 --name $name --quiet | head -1 | sed "s/^/$name /"
done
