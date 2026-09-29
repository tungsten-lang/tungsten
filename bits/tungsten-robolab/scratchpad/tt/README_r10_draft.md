### Table tennis: where P2 is lost, a bounce-tick artifact, and a screening design (round 10)

`skills/myo_tt_v11.w` (`MyoTTV11Skill < MyoTTV10Skill`, entry `lib/entry/myo_tt_v11.w`) adds the round-10 options, each off by default: `bk` (a guard for the
table-bounce tick), `kk` (a late pelvis kick, with the backhand's own `kk2_amp`, `kk2_k`, `kk2_v0`, `ns_k2`, `k_vpm2`), `ns_k` (aim pitch by serve speed), `pv` (a pelvis speed
governor), `qa` (a yaw-only forehand servo), `sg`, `ts_lead` / `bh_ts_lead` (the servo's start timed on the contact). With every option off it plays the round-5 champion serve for serve (60 of 60 and 40 of 40 P2 serves identical on every metric,
`out/tt_r10/chk_r10i.jsonl`, `chk_r10j.jsonl`). The parent skill got two hooks (`plan_ball`, `height_ball`), two parameters (`bh_p_z`, the backhand's proportional height gain; `fh_gain`, the forehand's arm reflex gain, the analogue of `bh_gain`) and a
`bh_box_dx` that may be negative, all defaulting to the old behaviour. Round 10 measured why `tt_p2_300` sits at 33% before it tried to move it: 600 fresh serves of the champion, per-serve time
series, an offline model of the return, and a fixed-serve screening design.

TODO_RESULT

**Tools** (`playground/`, all on a fast path that plays the same episodes as the standard one; `tt_fast.py check` compares them):

| tool | what it is |
| --- | --- |
| `tt_fast.py` | one env per worker process and a kinematics-only geometry sweep: setup CPU 1.7 s -> 0.13 s per episode, identical metrics |
| `tt_eval.py`, `tt_cmp.py`, `tt_summ.py` | resumable runs (JSON lines), the arena's paired sign-flip test plus the landing slack, per-side mechanics of a run |
| `tt_pools.py` | which seeds the side rule sends to each side (agrees with the controller on 600 of 600 seeds) |
| `tt_impact.py`, `tt_aimlaw.py`, `tt_ceiling.py` | the offline impact + flight model (predicts the outcome of 94% of clean hits), the aim law in Python, the success ceiling against execution noise |
| `tt_rsm.py`, `tt_rsm_run_params.py`, `tt_r10_compose.py` | a fixed-serve two-level random design regressed on the coded levels (main effects of 17 parameters from 33 runs), one run's parameter set, a candidate composed from a backhand and a forehand result |
| `tt_practice.py`, `tt_ilc.py`, `tt_cmc.py` | sep-CMA on common serves with a smooth score, the learned feed-forward on the fast path, a computed-muscle-control prototype |
| `tasks/myo_tt.py` | opt-in diagnostics only (`TT_SAVE_LOG`, `pelvis_vel`, `l8`, `pv`) |

TODO_BODY
