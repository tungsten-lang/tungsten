#!/bin/sh
# E2: the swing, aim, follow-through/recovery and the kc torque terms (MyoKickSkill, kick-a4 with kc 1) tuned on replays from the swing start of the noisy
# phase-1 dumps (noise 0.05 and 0.1, seeds 5000-5023 = 48 packs). Held out: seeds 5024-5071. x0 = the champion (kc gains 0).
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/kick/ksearch.py --init params/myo_kick_base.txt --controller bin/challengers/kick-a4 --kind swing \
  --dir kbase --glob 'kbase_n0.05_*' --glob 'kbase_n0.1_*' --seeds 5000:5024 \
  --only t_swing,hip_snap,th_k1,knee_k1,t_snap,th_k2,knee_k2,ankle_k,drv_hip,drv_knee,g_kick,g_anta,g_st,drv_st,aim_add,aim_rot,add_k,rot_k,kick_dy,aim_dy,t_follow,th_fol,knee_fol,drv_brake,drv_post,th_land,knee_land,ankle_land,rec_ldx,rec_rdx,rec_dz,fe_rec,t_rec,kc_rk,kc_rv,kc_yk,kc_ykd,kc_zk,kc_fk,kc_kk \
  --out scratchpad/kick/out/E2.txt --gens 40 --pop 14 --sigma 0.1 --seed 2 --note "E2 swing+aim+recovery+kc on replays from the swing start, noisy P1 dumps 0.05/0.1 seeds 5000-5023"
