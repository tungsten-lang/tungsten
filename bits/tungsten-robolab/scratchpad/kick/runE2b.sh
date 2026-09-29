#!/bin/sh
# E2b: the kc torque terms only (11 gains, x0 = 0) kr off (the champion's follow-through), replays from the swing start of the noisy phase-1 dumps (noise 0.05 and 0.1, seeds 5000-5023 = 48 packs).
cd /Users/erik/tungsten/bits/tungsten-robolab
exec .venv-myo/bin/python scratchpad/kick/ksearch.py --init params/myo_kick_base.txt --controller bin/challengers/kick-a8 --kind swing \
  --dir kbase --glob 'kbase_n0.05_*' --glob 'kbase_n0.1_*' --seeds 5000:5024 \
  --only kc_rk,kc_rv,kc_ak,kc_av,kc_yk,kc_ykd,kc_zk,kc_zv,kc_fk,kc_kk,kc_pa \
  --out scratchpad/kick/out/E2b.txt --gens 12 --pop 10 --sigma 0.12 --seed 5 --note "E2b kc gains on replays from the swing start, kr off, noisy P1 dumps 0.05/0.1 seeds 5000-5023"
