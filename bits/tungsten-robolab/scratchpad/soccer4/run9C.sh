#!/bin/sh
# clearance search C (9/29): the swing shank presses on the stance thigh with ~220 N in every hold and that sustained contact is what
# MuJoCo blows up on (the only late failures: 89106 at 222 s, 89122 at 15.8 s, 91049 at 16.5 s, 89103 at 255.6 s). Minimise the mean inter-leg force
# (weight 0.03 per N) with the hold as the constraint, starting from the shift-brake params, swing-leg and stance-posture parameters only (hold-phase
# changes: the pre-lift trajectory is identical across candidates). 5 s rollouts, 4 random training starts a generation: the force is systematic.
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/soccer4/search5.py --init params/myo_soccer_single_leg_310_shc.txt \
  --out scratchpad/soccer4/s9C2.txt --controller bin/challengers/soccer6-p \
  --seconds 5 --k_rand 4 --k_hard 0 --rand_lo 90000 --rand_hi 90400 --gens 30 --pop 8 --workers 4 --sigma 0.08 --leg_w 0.03 --leg_thr 0 --resume \
  --note "clearance search C2: mean inter-leg contact force down with the hold as the constraint (shift-brake base)" \
  --only b_sw_th,b_sw_knee,b_sw_ankle,b_sw_add,b_add,b_st_hip,b_st_knee,b_st_ankle,sb_lean,sb_drv_abd,b_t_lift,bc_in
