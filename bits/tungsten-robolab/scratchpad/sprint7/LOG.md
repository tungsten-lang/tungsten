# Sprint probe: does S5's spine-servo finding carry to the human-body sprinter? (main session, 3 Oct 2026)

Question: S5 found that the ES-tuned spine servo `k_sp` of the top gears was a destabiliser on the LABELLED beyond-human body (zeroing it, and using its opposite sign `k_sps` -0.06, stabilised the top gear). The human P95-body champion
`sprint_top_speed_v4_p95` (8.276 m/s on 12 starts; chain `params/run_gearx_v4_p95_x5a.txt`, RunGearXSkill, five gears) has nonzero k_sp in gears 3-5 (0.089 / 0.133 / 0.033). Does zeroing them help the human body?

Probe (`scratchpad/sprint7/human_ksp_probe.py`, 48 starts nobody used, 60001-60048, the champion record's own task `run_v4` and the trial's env, HUMAN P95 body; 30 s; survivors' mean of the fastest 1 s window):

| variant | falls | survivors' mean peak |
| --- | --- | --- |
| champion | 3 / 48 | 8.296 m/s |
| g3-g5 k_sp = 0 | 1 / 48 | 8.283 m/s |
| g3-g5 k_sp = k_spd = 0 | 37 / 48 | 8.055 m/s (n 11) |
| g5 k_sp = k_spd = 0 | 46 / 48 | 8.074 m/s (n 2) |

Reading: no speed gain (8.296 -> 8.283), the fall difference (3 -> 1 of 48) is inside the noise, and the spine DAMPING term k_spd is load-bearing (zeroing it as well collapses the runner). The human-body sprinter stays at about 8.3 m/s, 79 % of its 10.45 m/s ideal ceiling; the S5 mechanism is specific to the beyond-human chains (their k_sp was ES-tuned to 0.26 in gears 2-3). The opposite-sign `k_sps` needs RunGearYSkill and was not tried on the human chain. Nothing changed in the repo besides this note and the probe script (variants written to out/sprint7, git-ignored).
