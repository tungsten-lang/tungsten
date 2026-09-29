#!/bin/sh
# scan 2: around taim1 + arm_swing_kd 0.03 + train_end -0.01 (batting round 2), 16 maximin training pitches
cd /Users/erik/tungsten/bits/tungsten-robolab
TR=3008,3049,3050,3060,3064,3073,3074,3091,3092,3102,3107,3108,3115,3118,3127,3138
B="arm_swing_kd=0.03,train_end=-0.01"
for s in "$B" "$B,arm_swing_kd=0.01" "$B,arm_swing_kd=0.0" "$B,train_end=-0.02" "$B,train_end=-0.03" "$B,swing_kd=0.0" "$B,arm_swing_kp=13" "$B,arm_swing_kp=7" "$B,swing_kp=13" "$B,swing_kp=6" "$B,train_gain=1.3" "$B,train_gain=0.8"; do
  name=scan2_$(echo "$s" | sed 's/arm_swing_kd=0.03,train_end=-0.01,\?//' | tr '=,' '__')
  name=${name:-scan2_B}
  .venv/bin/python playground/bat_rep.py eval --params params/bat_r2_taim1.txt --controller bin/challengers/bat_r2-t1 --seeds $TR --set "$s" --seconds 4.3 --workers 2 --name "${name}" --quiet | head -1 | sed "s/^/${name} /"
done
