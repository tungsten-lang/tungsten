# State of the art: muscle-driven athletic skills (running, bat swing, dribbling, long jump, hurdling)

Compiled 2026-09-25 as a comparison brief for a MuJoCo muscle-actuated humanoid. It is driven by a contraction vector, uses minimum-jerk "chunks" and synergies, and latches transitions on sensor events.

**How to read this.**
- Every number has a source and a date.
- **Preprint** = arXiv, not peer-reviewed.
- **CO** = company claim; **PRESS** = news report only; **OFFICIAL** = competition result or record; **UNVERIFIED** = could not be confirmed from a primary source.
- Checking: most numbers were read from the primary PDF, HTML or project page by me or by one of three parallel research passes. I re-fetched the headline 2026 claims myself (Wang 2026 sprint, Lambda-Hold, Schumacher 2025, SMPLOlympics, the 2026 robot games, AthenaZero, the athletics world records).
- Coverage limit: the web-search budget ran out partway through the research passes, and later lookups went through arXiv, OpenAlex, Europe PMC and direct fetches. "None found" means none found in the sources reachable. Chinese-company demos and SIGGRAPH/CVPR 2026 papers may be under-covered.

## Headline findings

1. **Nothing published matches all five skills on a muscle-driven body.** Muscle-driven results exist only for running and a crude hurdling pass:
   - Running: Wang et al., 2026 preprint, peak 12.5 m/s, with 110 m hurdles in ~15 s over lowered hurdles.
   - Running on MuJoCo MyoLeg, peer-reviewed: 5.44 m/s (Schumacher et al. 2025).
   - Muscle-driven batting, dribbling and running long jump: **none found**. Being first in those three is a legitimate claim, provided the results are honest about assists.
2. **The architecture has direct precedents:**
   - Lambda-Hold (Aug 2026 preprint): per-muscle equilibrium-point commands held between ground-contact events. It reaches 6.5 m/s sprinting after ~1 h of training.
   - SIMBICON and Liu & Hodgins: contact-latched FSMs and control-fragment graphs.
   - SAR: a 20-synergy action space.
   - Flash & Henis 1991: minimum-jerk superposition for mid-movement target switches.
   - HITTER, Diff-Muscle and Vid2Player3D: predict the ball, plan the intercept, then track it.
3. **Real robots moved fast in 2026.** At the World Humanoid Robot Games (Aug 2026):
   - 100 m in 8.64 s.
   - Run-up long jump of 7.97 m.
   - Standing long jump of 4.83 m.
   A humanoid with a muscle-driven controller will not beat these numbers. Compare on human-likeness, robustness, energy and generality instead.
4. **Human records changed in 2026:**
   - 110 m hurdles: 12.75 s, Tharp, June 2026, pending ratification.
   - 100 m hurdles: 12.09 s, Russell, Aug 2026.
   - 400 m hurdles: 45.80 s, dos Santos, Aug 2026.
5. **MuJoCo-specific caveats:**
   - Rigid tendons: MuscleMimic needed 5x muscle force to jump.
   - Weaker EMG realism than Hyfydy: r 0.11 vs 0.40 (2026 preprint).
   - Wang 2026 reports that MuJoCo's constraint solver destabilized sprinting.
   Plan for strength scaling and report it.

## 1. Muscle-driven simulated humans

Legend: **MTU** = muscle-tendon unit. "Assist" = any non-muscle actuator or external force (residual/root force, reserve torque motor, position actuator). Preprints are marked **(preprint)**.

### 1.1 MyoSuite and the MyoChallenges (MuJoCo, rigid tendons)

MyoSuite: Caggiano, Wang, Durandau, Sartori, Kumar, L4DC 2022, PMLR 168:492-507 ([arXiv 2205.13600](https://arxiv.org/abs/2205.13600)). Models ([docs](https://myosuite.readthedocs.io/en/latest/suite.html), [myo_sim](https://github.com/MyoHub/myo_sim)): myoHand 39 muscles; myoArm 63 muscles / 27 DoF; myoTorso (MyoBack) 210 muscles; myoLeg 80 muscles (DoF count is reported inconsistently across sources: 16, 20, 28, 29); MyoFullBody 416 muscles / 123 joints. MuJoCo muscle actuators act on tendons of fixed length, so tendons store no elastic energy. That matters for jumping (see §1.6).

| Edition | Tracks | Phase-2 winner and score | Assist? | Notes |
|---|---|---|---|---|
| 2022, NeurIPS ([PMLR 220:233-250](https://proceedings.mlr.press/v220/caggiano23a.html)) | Die reorientation; Baoding balls (myoHand) | Die: IARAI-JKU 0.13 and pkumarl 0.12 (co-winners). Baoding: **stiff_fingers (Mathis lab) 0.55** | none | Curriculum RL (Chiappa et al., *Neuron* 112(23), 2024). Only muscle-driven "ball juggling"-type result found. |
| 2023, NeurIPS ([site](https://sites.google.com/view/myosuite/myochallenge/myochallenge-2023)) | Relocate (myoArm); Chase-Tag locomotion (myoLeg, 12x12 m arena) | Relocate: **Lattice 0.343**. Chase Tag: **GaitNet (SNU) 0.666** | none | No locomotion speeds published. |
| 2024, NeurIPS; paper at NeurIPS 2025 D&B ([PDF](https://papers.neurips.cc/paper_files/paper/2025/file/5a8f69523f9511a5706568c552de0ebb-Paper-Datasets_and_Benchmarks_Track.pdf)) | Bimanual handover to a prosthetic arm; myoOSL amputee locomotion over 100 m of mixed terrain | Handover: **Muscle Heads (UCL) 0.26** (9 learned synergies over 63 muscles). Locomotion: **MSKBioDyn (KAIST) 0.72**, PPO+AMP on mocap from 120 people, target 1 m/s, max **71.6 m** of 100 m | Prosthetic limbs are non-muscle actuators | 53 teams / 292 submissions. |
| 2025, NeurIPS, "Towards Human Athletic Intelligence" ([arXiv 2605.15650](https://arxiv.org/abs/2605.15650), 15 May 2026) | Table-tennis rally (myoArm+myoTorso, 273 muscles **+ 2 pelvis position actuators**); soccer penalty kick (myoLeg+myoTorso, 290 muscles, moving goalkeeper) | Table tennis: **ActingAI 64%** (planner + hierarchical RL; kinematics-to-muscle map cuts 273 to 32 action dims). Soccer: **Servette MyoClub 32% goals** (KINESIS teacher -> BC -> RL; ~14 days of training) | Table tennis: pelvis actuators | ~69 teams / 562 submissions. Only muscle-driven SPORT benchmarks. No ball, swing or run-up speeds reported. |
| 2026 | Not announced: absent from the 16 NeurIPS 2026 competitions ([NeurIPS blog, 28 Jul 2026](https://blog.neurips.cc/2026/07/28/neurips-2026-competitions-announced/)) | | | |

Post-challenge: Diff-Muscle (Zhao et al., arXiv [2603.08617](https://arxiv.org/abs/2603.08617), Mar 2026, **preprint**) on the MyoSuite table-tennis task: **hit rate 95.1%, success 80.3%**, up to 14 dual-agent rally exchanges (same 2 pelvis actuators).

### 1.2 Full-body musculoskeletal imitation and control

| System | Venue / date | Model | Method | Assist | Key numbers |
|---|---|---|---|---|---|
| Lee, Park, Lee, Lee, "Scalable Muscle-Actuated Human Simulation and Control" ([project](https://mrl.snu.ac.kr/research/ProjectScalable/Page.htm), [code](https://github.com/lsw9021/MASS)) | SIGGRAPH 2019, TOG 38(4):73 | 284-346 MTUs (not 326), DART | PPO mocap imitation + supervised muscle-coordination net | none at runtime | Walk, **run**, Sargent vertical jump, kick, cartwheel, pathological gaits; 12-36 h per skill. No speeds or jump heights reported. |
| Geijtenbeek, van de Panne, van der Stappen, "Flexible Muscle-Based Locomotion for Bipedal Creatures" ([project](https://www.cs.ubc.ca/~van/papers/2013-TOG-MuscleBasedBipeds/index.html)) | SIGGRAPH Asia 2013, TOG 32(6) | ~40 muscles, ODE | CMA-ES co-optimizes muscle routing + delayed feedback controller; no mocap | none | Human running at **4.0 m/s** (+/-3 deg slopes, 50 N pushes); at 2.0 m/s: +/-5 deg, 100 N, 12 deg/s turns. |
| Wang, Hamner, Delp, Koltun ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC4523558/)) | SIGGRAPH 2012 | 8 MTUs/leg on sagittal hip-knee-ankle, rest torque | FSM + reflexes, CMA-ES, metabolic objective | **hybrid: other joints torque-driven** | Running 2.0-5.0 m/s. |
| MuscleVAE (Feng, Xu, Liu) ([arXiv 2312.07340](https://arxiv.org/abs/2312.07340)) | SIGGRAPH Asia 2023 | 284 muscles, ODE | Model-based VAE with 3CC-r fatigue | none | Walk, run, hop/jump, jump spin kick. Qualitative only. |
| MS-Human-700 (Zuo, He, Shao, Sui) ([arXiv 2312.05473](https://arxiv.org/abs/2312.05473)) | ICRA 2024 | **700 MTUs**, 206 joints, MuJoCo + OpenSim | Hierarchical SAC over low-dim synergy representation | none reported | Walking, exo and prosthesis walking; returns only (no speeds). |
| MS-Emulator (Wei, Zuo, ..., Sui) ([arXiv 2603.29332](https://arxiv.org/abs/2603.29332)) | Mar 2026 **(preprint)** | ~700 muscles, MuJoCo Warp | Per-clip imitation | none reported | Walk, run, dance, **"run jump"**, cartwheel, backflip; joint error <=2 deg (walk / a running clip), <=7 deg and ~6 cm across dynamic clips; GRF r = 0.853. |
| KINESIS (Simos, Chiappa, Mathis) ([arXiv 2503.14637](https://arxiv.org/abs/2503.14637), [code](https://github.com/amathislab/Kinesis)) | ICRA 2026 (per README); v3 Mar 2026 | MyoLeg 80 muscles; v3 up to 290 (legs+back), MuJoCo | PPO + Lattice, mixture of experts, outputs activations | none | KIT-AMASS locomotion test: **96.91% success, MPJPE 42.84 mm** (v3 legs+back); v1: 91.47%, 47.31 mm. No speeds. |
| MuscleMimic (Li, Wang, ..., Mathis) ([arXiv 2603.25544](https://arxiv.org/abs/2603.25544)) | Mar 2026 **(preprint)** | MyoFullBody 416 muscles, MuJoCo Warp | PPO imitation | none, but **max isometric force x5 for vertical jumps** | Test success 92.62%, joint error 6.63 deg; running kinematics r = 0.81 vs 1.8 m/s treadmill data. |
| MAGNET (Park, Jung, Lee, Won) ([ACM](https://dl.acm.org/doi/10.1145/3721238.3730617)) | SIGGRAPH 2025 | 284 muscles, DART | Torque policy -> muscle-coordination net -> adaptation | final model muscle-only | Run, jump kick, backflip, cartwheel. No speeds. |
| FreeMusco (Kim & Lee) ([arXiv 2511.14205](https://arxiv.org/abs/2511.14205)) | SIGGRAPH Asia 2025 | 120 muscles, MuJoCo | Model-based RL, no mocap | none | Walking at 1.16 m/s; "high-energy running", no speed given. |
| KinTwin (Cotton) ([arXiv 2505.13436](https://arxiv.org/abs/2505.13436)) | 2025 | 92 muscles, MuJoCo MJX | Imitation | **6-DoF pelvis residual force** | Clinical gait; joint error 1.68 deg. |
| MSK-Bench (Ou et al.) (arXiv 2609.26872) | Sep 2026 **(preprint)** | 416 muscles, MuJoCo | Benchmark, 22 tasks incl. running, jumping, **hurdles** | "residual" = residual muscle action, not a force | Locomotion-family success: DynSyn-SAC 81.33%, DEP-RL 41.33%, SAC/PPO 0%. Per-task hurdle numbers UNVERIFIED. |
| Ahmad, Borden, Tucker, "Beyond Kinematics" (arXiv 2609.21909) | Sep 2026 **(preprint)** | Same imitation in Hyfydy vs MuJoCo/MyoSim | | | Kinematics comparable, but EMG agreement **Hyfydy r 0.40 (RMSE 0.164) vs MuJoCo r 0.11 (RMSE 0.344)**. Key fidelity caveat for a MuJoCo build. |

### 1.3 Deep RL without demonstrations, reflex and synergy action spaces

| System | Venue / date | Model | Assist | Key numbers |
|---|---|---|---|---|
| **Wang, Bianco, Tevet, Hicks, Liu, Delp, Fatahalian, "Learning Realistic Athletic Sprinting Without Demonstrations"** ([arXiv 2609.11083](https://arxiv.org/abs/2609.11083)) | 10 Sep 2026 **(preprint)** | 136 MTUs, 31 DoF, 1.79 m / 75.3 kg, max isometric forces doubled; custom GPU simulator "Bolt" (~1000x real-time); FastTD3 on raw excitations; reward = speed - joint-limit "pain" + alive | none (only light 5 N m/rad upper-limb stiffness) | **Peak 12.5 +/- 0.5 m/s** vs the modelled athlete's measured 9.65 +/- 0.25; **100 m in ~10 s**; **110 m hurdles ~15.0 s** over hurdles of 0.7-1.0 m (below the regulation 1.067 m) with stutter steps and trail-leg landings; standing vertical jump with hand reach ~2.85 m. Limits: GRF ~2 BW too high; authors report MuJoCo's constraint solver made sprints unstable. **Most important competitor for running and hurdles.** |
| Schumacher, Geijtenbeek, Caggiano, Kumar, Schmitt, Martius, Haeufle, "Natural and robust walking using RL without demonstrations..." ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC12002607/)) | *iScience* 28:112203, 2025 | DEP-RL; H0918, H1622, H2190 (Hyfydy), **MyoLeg (MuJoCo)** | none | Max running speed: H2190 (90 muscles) **6.49 m/s**; **MyoLeg 5.44 m/s** (with strong lateral trunk oscillation); H0918 5.38; H1622 5.04. **Best peer-reviewed MuJoCo muscle running speed.** |
| DEP-RL (Schumacher, Haeufle, Buechler, Schmitt, Martius) ([arXiv 2206.00484](https://arxiv.org/abs/2206.00484)) | ICLR 2023 | 50-muscle arm, 120-muscle ostrich, 18-muscle planar human | none | Human run: 5/5 seeds symmetric gait vs 1/5 for MPO; hop CoM >1.08 m. |
| SAR (Berg, Caggiano, Kumar) ([arXiv 2307.03716](https://arxiv.org/abs/2307.03716)) | RSS 2023 | 20 synergies (ICA+PCA, >80% variance) for myoLeg 80 and myoHand 39 | none | Walk 11.7 m vs 0.8 m end-to-end; >70% vs <20% success on 100+ object manipulation. **Direct precedent for the synergy layer.** |
| Lambda-Hold (Lee, Lee, Ahn) ([arXiv 2608.17030](https://arxiv.org/abs/2608.17030)) | 17 Aug 2026 **(preprint)** | H2190 in SCONE/Hyfydy; policy sets per-muscle EP threshold lambda, held between GRF events | none | 4.7 m/s; **6.5 m/s** with force-velocity curriculum; ~1 h training. See §3; **nearest architectural match to our design.** |
| Bunz, Haeufle, Schmitt, Geijtenbeek ([Commun Biol](https://doi.org/10.1038/s42003-025-09307-x)) | 2025 | Planar 18 muscles, reflex-only, Hyfydy | none | Max running 3.42 m/s; hopping, skipping, backward running. |
| Bunz, Bruel, Ijspeert, Schmitt ([Sci Rep 16:13028](https://www.nature.com/articles/s41598-026-48509-z)) | 2026 | Reflex modulation | none | Running 2.0-3.4 m/s with online walk-run transitions. |
| Song & Geyer ([J Physiol](https://doi.org/10.1113/JP270228)) | 2015 | 3-D, 22 muscles, reflex + supraspinal layer | none | Walking 0.8-1.8 m/s; running at 3 m/s but falls after ~20 m; obstacle clearing while walking. |

### 1.4 Predictive (trajectory-optimization) sprinting and jumping

| Study | Model | Assist | Result |
|---|---|---|---|
| Miller, Umberger, Caldwell, *J Biomech* 45:1092, 2012 ([PDF](https://www.umass.edu/locomotion/pdfs/job-2012a.pdf)) | 2D, 18 muscles | arm swing as a shoulder force | Predicted max speed **6.75 m/s** (subjects 6.42); 7.76 m/s without force-velocity; 8.24 m/s torque-driven. |
| Van Wouwe, Hicks, Delp, Liu, *PLOS Comput Biol* 20(2):e1011410, 2024 ([link](https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1011410)) | 31 DoF, 92 muscles | **8 torque actuators (arms)** | 8.13 m/s generic; 9.49 m/s with optimized segment dimensions; 8.88 m/s trained muscle volumes. |
| Haralabidis, Eaton, Delp, Hicks, *MSSE* 57(12):2807, 2025 ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC12893165/)) | 37 DoF, 92 MTUs, one symmetric step | **MTP reserves + 14 upper-limb torque actuators** | **11.85 m/s** top speed (single step). |
| Falisse et al., *J R Soc Interface* 16:20190402, 2019 ([doi](https://doi.org/10.1098/rsif.2019.0402)) | 3D, 29 DoF, 92 muscles | 8 arm torque actuators | 0.73-2.73 m/s; predicted walk-run transition 2.23 m/s (humans 1.89-2.16). |
| Emonds, Funken, Potthast, Mombaur ([arXiv 2608.22507](https://arxiv.org/abs/2608.22507)) | Aug 2026 **(preprint)**; **torque-driven** 31-DoF rigid multibody, MUSCOD-II | n/a | Running long jump synthesized **9.86 m** (takeoff angle 20.1 deg) vs reconstructed athlete 7.58 m; amputee with prosthesis 8.29 m -> 9.22 m. |
| Ashby & Delp, *J Biomech* 2006; Ong, Hicks, Delp, *IEEE TBME* 2016 | torque-driven | n/a | Standing long jump 2.00 m (arms free) vs 1.60 m (arms restricted); 2.27 m. |

**Gaps (muscle-driven, as of 2026-09-25):** no running long jump, bat swing, basketball dribble or regulation-height hurdle simulation was found. Searched: arXiv, OpenAlex, Europe PMC, web. A 2025 PRISMA review of predictive simulation (Denayer et al., *JNER*) lists no throwing, batting, basketball or hurdling studies.

### 1.5 NeurIPS osim-rl challenges (OpenSim, pure muscle excitations, no assist)

| Year | Model | Winner / best score | Speed |
|---|---|---|---|
| 2017 "Learning to Run" ([arXiv 1804.00198](https://arxiv.org/abs/1804.00198), [1804.00361](https://arxiv.org/abs/1804.00361)) | 2D, 9 DoF, 18 muscles | NNAISENSE (PPO); best score **45.97 m in 10 s**; 442 teams | ~4.6 m/s average from a standing start (derived) |
| 2018 "AI for Prosthetics" ([arXiv 1902.02441](https://arxiv.org/abs/1902.02441)) | 3D, 14 DoF, 19 muscles, passive prosthesis | **Firework 9981**/10000 (DDPG), NNAISENSE 9950; 425 teams | Round 1 target 3 m/s; winner: "fastest running ... over 4.0 m/s" |
| 2019 "Learn to Move - Walk Around" (Song et al., *JNER* 18:126, 2021, [PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC8365920/)) | 3D, 22 muscles | **PARL (Baidu) 1490.07**; 323 teams | Curriculum began "run as fast as possible", then 3.0, 2.0 and 1.3 m/s |

### 1.6 Takeaways for a MuJoCo muscle build

1. Explosive skills: MuJoCo's rigid tendons store no elastic energy. MuscleMimic needed 5x max isometric force to jump; Wang 2026, Van Wouwe 2024 and Haralabidis 2025 doubled or scaled forces for elite sprinting. **Report any strength scaling** as part of results.
2. Physiological fidelity: EMG agreement in MuJoCo imitation is much weaker than in Hyfydy (r 0.11 vs 0.40, 2026 preprint). Report EMG correlation if claiming "human-like".
3. Synergy action spaces make it tractable: SAR (20 synergies), the MyoChallenge 2024 winner (9), and the 2025 table-tennis winner (32-D kinematic proxy).
4. Assists are routine in trajectory optimization and in MyoChallenge 2025 table tennis; the RL and imitation leaders (KINESIS, MuscleMimic, Schumacher 2025, Wang 2026) are muscle-only. **Claim "no residual forces" only if true.**

## 2. Physics-based character animation for the five skills (mostly torque/PD)

"PD" = the policy outputs PD targets that are converted to joint torques. "RFC" = residual force control (external wrenches).

### 2.1 Running / general imitation

| System | Venue | Actuation / data / method | Assist | Numbers |
|---|---|---|---|---|
| DeepMimic ([arXiv 1804.02717](https://arxiv.org/abs/1804.02717)) | SIGGRAPH 2018 | PD, mocap, PPO | none | Run return 0.951; Jump 0.947; baseball **pitch** 0.785; pitch-to-target 75% (imitation + task). |
| AMP ([arXiv 2104.02180](https://arxiv.org/abs/2104.02180)) | SIGGRAPH 2021 | PD, mocap, adversarial prior | none | Target speed 1-5 m/s (fast run ~4.5 m/s); soccer-dribble return 0.78. |
| ASE ([arXiv 2205.01906](https://arxiv.org/abs/2205.01906)) | SIGGRAPH 2022 | PD, 37 DoF | none | Speed task 0-7 m/s; upright running at ~7 m/s: **fastest stated PD graphics character**. |
| PHC ([arXiv 2305.06456](https://arxiv.org/abs/2305.06456)) | ICCV 2023 | PD, SMPL, AMASS | **none (explicit)** | AMASS test 96.4% success, MPJPE-g 47.4 mm. UHC (with RFC) 96.4%; UHC without RFC **62.6%**. |
| PULSE / PHC+ ([arXiv 2310.04582](https://arxiv.org/abs/2310.04582)) | ICLR 2024 | PD, 500 N m cap | none | PHC+ 100% / 99.2% (train/test), MPJPE-g 26.6 / 36.1 mm; max AMASS running ~5 m/s. |
| MaskedMimic ([arXiv 2409.14393](https://arxiv.org/abs/2409.14393)) | SIGGRAPH Asia 2024 | PD | none | Full-body tracker 99.9% test, MPJPE-g 31.3 mm. |
| UHC ([arXiv 2106.05969](https://arxiv.org/abs/2106.05969)); RFC ([arXiv 2006.07364](https://arxiv.org/abs/2006.07364)); SimPoE ([arXiv 2104.00683](https://arxiv.org/abs/2104.00683)) | NeurIPS 2021 / NeurIPS 2020 / CVPR 2021 | PD | **residual root/contact forces** | UHC AMASS 97.0%, 24.45 mm; SimPoE H36M 56.7 mm (115.2 mm without root force). |
| Yu, Turk, Liu, "Symmetric and Low-Energy Locomotion" ([arXiv 1801.08093](https://arxiv.org/abs/1801.08093)) | SIGGRAPH 2018 | torque, no mocap | assist forces during training only (curriculum to zero) | Runs at 5 m/s. |
| ADD ([arXiv 2505.04961](https://arxiv.org/abs/2505.04961)) | SIGGRAPH Asia 2025 | PD | none | Run position error 0.165 m (DeepMimic 0.013); parkour Double Kong 0.030 m. |
| SONIC (NVIDIA) ([arXiv 2511.07820](https://arxiv.org/abs/2511.07820)) | 2025, venue UNVERIFIED | PD, Unitree G1 model | none | 99.6% tracking success, 23.8 mm; near-100% survival to ~4 m/s in MuJoCo sim-to-sim. |
| BeyondMimic ([arXiv 2508.08241](https://arxiv.org/abs/2508.08241)) | 2025 | PD, real G1 | none | >50 m continuous running; no m/s given. |

### 2.2 Bat swing / striking a moving ball

**No physics-based baseball-batting character or humanoid simulation was found** (graphics + robotics, arXiv title/abstract search, awesome-humanoid-ball-sports list). Closest analogues:

| System | Venue | Actuation | Assist | Numbers |
|---|---|---|---|---|
| Vid2Player3D, "Learning Physically Simulated Tennis Skills from Broadcast Videos" ([project](https://xbpeng.github.io/projects/Vid2Player3D/)) | SIGGRAPH 2023 | PD, video-derived motion VAE + high-level policy predicting the future ball | **residual root force/torque by default** | Incoming 25-35 m/s. Median hit rate 0.92 (Federer/Djokovic); without residual forces avg hit 0.78 vs 0.89. Ablation: removing future-ball observation drops bounce-in 0.81 -> 0.30. **Evidence that predicted-trajectory inputs are what make re-aimed strikes work.** |
| Wang, Hodgins, Won, table tennis ([arXiv 2407.16210](https://arxiv.org/abs/2407.16210)) | SIGGRAPH 2024 | PD, MoE | none | 10.93 consecutive hits; landing error 0.26 m; 0.78 win rate vs humans. |
| SMPLOlympics ([arXiv 2407.00187](https://arxiv.org/abs/2407.00187)) | 2024 (preprint) | PD, 500 N m cap, Isaac Gym | none | Golf club hit 99.9% (PULSE); tennis avg 3.95 hits (AMP). No baseball environment. |
| Diff-Muscle / MyoChallenge 2025 table tennis (§1.1) | 2026 | **muscle** | 2 pelvis actuators | 80.3% success / 95.1% hit (Diff-Muscle); 64% (challenge winner). |
| LATENT, Unitree G1 tennis (arXiv 2603.12686) | Mar 2026 (preprint) | PD, MuJoCo/MJX -> real | none | Sim forehand 96.52% returns within 2.5 m; real forehand 90.90%. |
| HITTER, G1 table tennis (arXiv 2508.21043) | 2025 | PD, planner predicts strike pose/velocity/time + RL whole-body tracker | none | Real: 96.2% hit, 92.3% return (26 balls); 106-shot rally. |

The reusable pattern is a layered one: (1) predict the ball; (2) plan the implement pose, velocity and time at intercept; (3) track it with a low-level controller. HITTER, Diff-Muscle and Vid2Player3D all use it, and it maps directly onto a re-aimed minimum-jerk chunk. Mocap: CMU subject #124 has "Baseball Swing" and "Baseball Bunt".

### 2.3 Basketball dribbling (all torque/PD; no muscle-driven dribbling found)

| System | Venue | Method | Assist | Numbers |
|---|---|---|---|---|
| Liu & Hodgins, "Learning Basketball Dribbling Skills Using Trajectory Optimization and Deep RL" ([PDF](https://libliu.info/Basketball/Basketball.pdf)) | SIGGRAPH 2018, TOG 37(4):142 | Stable PD, ODE; SAMCON locomotion + CMA-ES arm trajectory opt + DDPG arm policies + control graphs; mocap without ball | none | Running dribble cycle 0.6 s; transitions over 1000 trials: between-legs 99.4%, behind-back 99.6%, front crossover 98.1%, spin crossover 95.7%; robust to ball restitution 0.78-0.82. **Closest to our design (control graph of skill chunks).** |
| PhysHOI ([arXiv 2312.04393](https://arxiv.org/abs/2312.04393)) | Dec 2023 (venue UNVERIFIED) | PD, contact-graph reward | none | BallPlay-V 82.4% success. |
| SkillMimic ([arXiv 2408.15270](https://arxiv.org/abs/2408.15270)) | CVPR 2025 (Highlight) | PD, 35 min BallPlay-M mocap | none | Dribble-forward 79.6%; layup 99.1%; shot 97.9%. |
| SkillMimic-V2 ([arXiv 2505.02094](https://arxiv.org/abs/2505.02094)) | SIGGRAPH 2025 | PD | none | Dribble forward/left/right 97.7/98.5/99.1%; skill transitions 93.8% (SkillMimic 15.1%). |
| Xu et al., "Learning to Ball: Composing Policies for Long-Horizon Basketball Moves" ([arXiv 2509.22442](https://arxiv.org/abs/2509.22442)) | SIGGRAPH Asia 2025, TOG 44(6) | PD, policy integration + high-level router, no ball-trajectory reference | none | Dribbles at commanded 0-5 m/s; catching 98.3%; shoot-off-the-dribble 91.8%. |
| HumanX ([arXiv 2602.02473](https://arxiv.org/abs/2602.02473)) | Feb 2026 (preprint) | PD, real Unitree G1 | none | Real: dribble 8/10, layup 7/10, jump shot 8/10. |
| g1-brunson ([GitHub](https://github.com/AmoghShrivastava/g1-brunson)) | 2026, not peer-reviewed | G1 in MuJoCo MJX, PPO | none | 44.3 between-the-legs crossovers per 20 s, 0/12 falls; ball calibrated 1.8 m drop -> 1.30 m rebound. |

### 2.4 Long jump / high jump

| System | Venue | Actuation / method | Numbers |
|---|---|---|---|
| Yin, Yang, van de Panne, Yin, "Discovering Diverse Athletic Jumping Strategies" ([arXiv 2105.00371](https://arxiv.org/abs/2105.00371)) | SIGGRAPH 2021 | Stable PD (biomechanical torque limits), PyBullet; Bayesian diversity search + PPO; run-up from one mocap clip, no jump mocap; no assist | High jump: **Fosbury 2.00 m**, straddle 1.95 m; obstacle jump (0.5 m box) width 2.50 m. Long jump shown in video only; no distance reported ("limited by run-up speed"). |
| SMPLOlympics (above) | 2024 | PD, 20 m runway | Long jump: **PULSE 5.105 m avg, 100% success**; PPO 19.42 m, 53.6% success (non-human exploit); AMP 0%. High jump: PULSE 100% at 1.0 m and 1.5 m bars (Fosbury-like). |
| Emonds et al. (§1.4) | 2026 preprint | torque, optimal control | **9.86 m** synthesized. |

### 2.5 Hurdling

| System | Venue | Actuation | Numbers |
|---|---|---|---|
| SMPLOlympics ([arXiv 2407.00187](https://arxiv.org/abs/2407.00187)) | 2024 | PD, 500 N m cap; curriculum over 0-1.167 m hurdles | **110 m, 10 x 1.067 m hurdles: PULSE 100% success, 17.76 s** (~6.2 m/s derived); PPO 57.6% / 11.22 s with unnatural bouncing; AMP 0%; 0% without curriculum. |
| Wang et al. 2026 (§1.3) | preprint | **muscle** | ~15.0 s over 0.7-1.0 m hurdles, poor technique. |
| Humanoid Parkour Learning (Zhuang et al.) ([arXiv 2406.10759](https://arxiv.org/abs/2406.10759)) | CoRL 2024 | PD, Unitree H1, no mocap | Sim hurdles 0.05-0.5 m, 100% over 10 runs; real 0.25 m foam hurdles at 1.8 m/s. |

Obstacle-course analogues: DeepMimic obstacle run (0.285 return), AMP run-leap-roll (0.27), PARC vaults (SIGGRAPH 2025). CMU mocap has no hurdle clips (subject #127 has obstacle jumps), so hurdling requires either synthesis or new capture.

## 3. Classic finite-state / feedback controllers and motor-control theory that match the chunk design

| Work | Venue / date | What it is | Actuation / method | Numbers and relevance |
|---|---|---|---|---|
| Hodgins, Wooten, Brogan, O'Brien, "Animating Human Athletics" | SIGGRAPH 1995 ([ACM](https://dl.acm.org/doi/10.1145/218380.218414), [arXiv reprint](https://arxiv.org/abs/2302.06108)) | Running, bicycling, handspring vault | Torque PD servos; per-behavior finite-state machine (running: flight, heel contact, heel-toe, toe contact phases) | Runner 17 segments / 30 controlled DoFs; runs 2.5-5 m/s. The original "phase-latched" athletic controller; closest ancestor of sensor-latched chunks. |
| Yin, Loken, van de Panne, "SIMBICON" | SIGGRAPH 2007, ACM TOG 26(3) ([paper](https://www.cs.ubc.ca/~van/papers/2007-siggraph-simbicon.pdf)) | Pose-control FSM with foot-contact-triggered state transitions and swing-hip balance feedback | Torque PD; hand-authored or mocap-informed | Walking in all directions, running, skipping, hopping; push-robust in 2D and 3D. Direct template for "latch on contact event" transitions. |
| Coros, Beaudoin, van de Panne, "Generalized Biped Walking Control" | SIGGRAPH 2010, ACM TOG 29(4) ([ACM](https://dl.acm.org/doi/10.1145/1778765.1781156)) | PD tracking + inverted-pendulum foot placement + Jacobian-transpose virtual forces | Torque | Walking skills incl. stepping over obstacles, carrying/pushing crates, climbing steps (no running). Model for real-time foot-placement corrections. |
| Wang, Fleet, Hertzmann, "Optimizing Walking Controllers" / "...for Uncertain Inputs and Environments" | SIGGRAPH Asia 2009 TOG 28(5); SIGGRAPH 2010 TOG 29(4) ([project](https://www.dgp.toronto.edu/~jmwang/optuie/)) | SIMBICON-style controllers with parameters optimized (CMA) under Monte-Carlo noise | Torque | Walking only. Shows how to tune FSM chunk parameters for robustness: optimize expected return over perturbation distributions. |
| Wang, Hamner, Delp, Koltun, "Optimizing Locomotion Controllers Using Biologically-Based Actuators and Objectives" | SIGGRAPH 2012, TOG 31(4) ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC4523558/)) | FSM (stance/swing substates) + reflex feedback (force/length) + neural delays 5-20 ms | 8 Hill-type MTUs per leg on sagittal hip/knee/ankle; remaining 30-DoF body PD; CMA-ES on 124 params, metabolic-energy objective | Walking 1.0-1.75 m/s; running 2.0-5.0 m/s; joint-angle standard scores 1.04-2.06 vs 1.73-6.75 for prior methods (20-subject treadmill data). The closest pre-deep-RL muscle-driven running controller. |
| Kwon & Hodgins, "Control Systems for Human Running using an Inverted Pendulum Model and a Reference Motion Capture Sequence" | SCA 2010 ([EG DL](https://diglib.eg.org/items/ffd5ac7e-9a63-40a3-b761-44fe213757a5)) | IP-on-cart balance planner + mocap reference | Torque | Running with speed changes and turns. |
| Liu & Hodgins, "Learning to Schedule Control Fragments ... Using Deep Q-Learning" | ACM TOG 36(3) 2017 ([ACM](https://dl.acm.org/doi/10.1145/3072959.3083723)) | Library of short open-loop control fragments re-ordered at runtime by a learned scheduler | Torque; SAMCON-derived fragments + DQN | Running, skateboarding, walking on a ball, bongo board, breakdancing. The most direct graphics precedent for "chunks + learned transition policy". |
| Geyer & Herr, "A Muscle-Reflex Model That Encodes Principles of Legged Mechanics..." | IEEE TNSRE 18(3), 2010 ([MIT OA PDF](https://dspace.mit.edu/bitstream/handle/1721.1/70926/)) | Reflex-only (no CPG) muscle controller; stance/swing reflexes latched on ground contact | 7 muscles/leg, 2D | Walking; reproduces human kinematics/muscle activity, tolerates ground disturbances and slopes. |
| Song & Geyer, "A neural circuitry that emphasizes spinal feedback generates diverse behaviours of human locomotion" | J Physiol 593:3493-3511, 2015 ([Wiley](https://physoc.onlinelibrary.wiley.com/doi/abs/10.1113/JP270228)) | Extended 3-D reflex controller with supraspinal layer for foot placement | 11 muscles/leg, 3D | Walking (0.8-1.8 m/s) and running, accel/decel, slopes, stairs, turning, obstacle avoidance; the 3 m/s run falls after ~20 m. Basis of the SCONE reflex controllers. |
| Feldman, equilibrium-point (lambda) hypothesis | J Motor Behavior 18(1):17-54, 1986 ([T&F](https://www.tandfonline.com/doi/abs/10.1080/00222895.1986.10735369)); original 1966 Biophysics | Descending command = stretch-reflex threshold length lambda per muscle; movement = shifting equilibrium | Theory | Our "contraction percent" vector is closest to a lambda command. See the 2026 lambda-hold paper below for a working RL implementation. |
| Flash & Hogan, minimum-jerk model | J Neurosci 5(7):1688-1703, 1985 ([JNeurosci](https://www.jneurosci.org/content/5/7/1688)) | Hand path minimizes integrated squared jerk: quintic position profile, bell-shaped velocity | Theory + planar arm experiments | Justifies quintic easing within a chunk. |
| Flash & Henis, "Arm Trajectory Modifications During Reaching Towards Visual Targets" | J Cogn Neurosci 3(3), July 1991 ([PubMed](https://pubmed.ncbi.nlm.nih.gov/23964837/)) | Double-step target jumps (10-110 ms ISI): the correction is the vector SUPERPOSITION of the original min-jerk unit and a second min-jerk unit from the old to the new target | Theory + experiments | Exactly the mechanism for re-aiming a bat swing mid-chunk without restarting it. |
| Todorov & Jordan, "Optimal feedback control as a theory of motor coordination" | Nat Neurosci 5:1226-1235, 2002 ([Nature](https://www.nature.com/articles/nn963)) | Minimal-intervention principle: correct only task-relevant deviations | Theory | Argues corrections should be projected onto task space (e.g. bat-ball intercept), not onto the whole muscle vector. |
| d'Avella, Saltiel, Bizzi, "Combinations of muscle synergies in the construction of a natural motor behavior" | Nat Neurosci 6(3):300-308, 2003 ([Nature](https://www.nature.com/articles/nn1010)) | Three time-varying synergies, scaled and time-shifted, explain frog kicking in all directions | EMG decomposition | Model for a chunk = weighted, time-shifted synergy bundle. |
| Ivanenko, Poppele, Lacquaniti 2004 (J Physiol) and Cappellini, Ivanenko, Poppele, Lacquaniti, "Motor Patterns in Human Walking and Running" | J Neurophysiol 95(6):3426-3437, 2006 ([APS](https://journals.physiology.org/doi/full/10.1152/jn.00081.2006)) | ~5 temporal activation components shared by walking and running; in running one stance component shifts earlier | EMG, 32 muscles | Human-data prior for running synergies: 5 basis patterns per gait cycle. |

**Newest work that implements this exact design (2026):** Lee, Lee, Ahn, "Lambda-Hold Control: Human-Like Movement Emerges from a Minimal Task Reward in Predictive Musculoskeletal Simulation", arXiv 2608.17030, submitted 2026-08-17 (preprint, not peer-reviewed) ([arXiv](https://arxiv.org/abs/2608.17030)). SCONE + Hyfydy, H2190 model (3D, 21 DoF, 90 MTUs). The policy outputs per-muscle equilibrium-point thresholds lambda, a stretch-reflex law turns them into excitations, and the command is **held between ground-reaction-force events** (foot strike / toe-off plus interpolated sub-points; holds 0.05-0.15 s, about 8 decisions per gait cycle). Sprint speed 4.7 m/s unmodified, **6.5 m/s** with a force-velocity curriculum; about 4.0 m/s within 10M sim steps; ~1 h wall-clock on one RTX 5070; ~100x fewer policy decisions than direct-excitation RL. Baselines: plain SAC on excitations, excitation-hold, DEP-RL, 30-D NMF synergy. EMG agreement vs Van Hooren & Meijer at 5.0 m/s: mean r = 0.42 (plantarflexors r > 0.80, swing-phase thigh muscles poor). This is the nearest published analogue to "contraction-percent vector held in event-latched chunks" and should be treated as the direct baseline for running.

## 4. Real humanoid robots (2024 to Sep 2026)

Status labels: **OFFICIAL** = competition result or Guinness record; **PR** = peer-reviewed; **arXiv** = preprint; **CO** = company claim; **PRESS** = news report only.

### 4.1 Running

| Result | Robot / org | Date | Status | Source |
|---|---|---|---|---|
| **100 m in 8.64 s** (Games record; ~11.6 m/s average, derived). Earlier rounds: 9.39 s (22 Aug), 8.86 s (25 Aug) | Tiangong Ultra, Beijing Humanoid Robot Innovation Center (X-Humanoid), 2026 World Humanoid Robot Games (WHRG), Beijing | 26 Aug 2026 | OFFICIAL (via press) | [CGTN](https://news.cgtn.com/news/2026-08-27/Tiangong-Ultra-sets-100m-record-as-World-Humanoid-Robot-Games-close-1PWx9LjZDC8/p.html), [Global Times](https://www.globaltimes.cn/page/202608/1369085.shtml), [Al Jazeera/Reuters](https://www.aljazeera.com/sports/2026/8/25/chinese-robot-tiangong-clocks-sub-9-second-100-metres-in-beijing) |
| 400 m 38.15 s; 1500 m 2:21.64 (2025 bests: 1:28.03 and 6:34.40) | Tiangong / Tianzhuo teams, 2026 WHRG | 23 Aug 2026 | OFFICIAL | [Xinhua live](https://www.news.cn/sports/20260824/f6eaa13b7b434f2cb47134e34cb606ae/c.html), CGTN. The 1500 m average (~10.6 m/s) exceeding the 400 m average is anomalous as reported. |
| Peak 14.5 m/s; 100 m 9.32 s in a pre-Games test | Honor "Lightning" (169 cm, 95 cm legs, ~400 N m leg torque) | Aug 2026 | PRESS, unverified | [NBC News](https://www.nbcnews.com/tech/tech-news/chinese-humanoid-robot-lightning-beats-human-100m-world-record-rcna593869) |
| Peak 12.66 m/s over a short stretch | Unitree "Superman" | 18 Aug 2026 | CO, "not independently verified" | [Singularity Hub](https://singularityhub.com/2026/08/24/unitree-claims-new-humanoid-robot-outruns-usain-bolt/) |
| Peak 10.1 m/s (Unitree flagged possible measurement error) | Unitree H1 | 12 Apr 2026 | CO | [heise](https://www.heise.de/en/news/Unitree-s-humanoid-H1-robot-reaches-10-1-m-s-in-the-100m-sprint-11255951.html) |
| Peak 10 m/s | MirrorMe "Bolt" (175 cm, 75 kg) | 3 Feb 2026 | CO | [CnEVPost](https://cnevpost.com/2026/02/03/mirrorme-unveils-worlds-fastest-humanoid-robot-bolt/) |
| Half-marathon 50:26, autonomous (~7.0 m/s average) | Honor "Lightning", Beijing E-Town | 19 Apr 2026 | OFFICIAL (via press) | [Xinhua](https://english.news.cn/20260419/74fc74a78dc64d959fbd4c1f244f6561/c.html) |
| Half-marathon 2:40:42 (remote-controlled, 3 battery swaps) | Tiangong Ultra | 19 Apr 2025 | OFFICIAL (via press) | [CNN](https://www.cnn.com/2025/04/19/asia/china-first-humanoid-robot-half-marathon-intl-hnk) |
| 2025 WHRG: 100 m 21.50 s (Tiangong Ultra); Unitree H1 400 m 1:28.03, 1500 m 6:34.40; in-race top speed 4.78 m/s | various | 15-17 Aug 2025 | OFFICIAL | [ithome](https://www.ithome.com/0/876/504.htm) |
| Unitree H1 3.3 m/s ("world's fastest" at the time) | Unitree | Mar 2024 | CO (no Guinness page found) | [GIGAZINE](https://gigazine.net/gsc_news/en/20240314-unitree-h1-world-fastest-humanoid-robot/) |
| Guinness "fastest 100 m by a bipedal robot": 24.73 s | Cassie (Oregon State; biped, not humanoid) | 11 May 2022 | OFFICIAL (not visibly updated) | [Guinness](https://www.guinnessworldrecords.com/world-records/629600-fastest-100-m-by-a-bipedal-robot) |
| Western humanoids: Tesla Optimus running video (Dec 2025, no speed); Figure 03 spec 1.3 m/s; BD electric Atlas no official speed; Agility Digit "3-4 mph" | | 2025-2026 | CO/PRESS | [IE, Optimus](https://interestingengineering.com/ai-robotics/optimus-humanoid-robot-masters-running), [IE, Figure](https://interestingengineering.com/ai-robotics/figure-humanoid-nears-human-jogging-pace) |

### 4.2 Jumping

| Result | Robot | Date | Status | Source |
|---|---|---|---|---|
| **Long jump 7.97 m** (attempts 7.32 / 7.62 / 7.97; described as a run-up jump; measurement rules not verified); 2nd 7.24 m; only 6 of 21 teams recorded valid jumps | Tiangong Ultra, Tianjiao team, 2026 WHRG | 23 Aug 2026 (reported 24 Aug) | OFFICIAL (via press) | [Bastille Post](https://www.bastillepost.com/global/article/6102281-humanoid-robot-wins-gold-with-7-97-meter-jump-at-2nd-world-humanoid-robot-games), [BJD](https://xinwen.bjd.com.cn/content/s6a8afa37e4b03fa51a834983.html) |
| **Standing long jump 4.83 m** (2025 winner: 1.25 m, Noetix) | Tiangong Ultra, Tianzhuo team | 26 Aug 2026 | OFFICIAL | [BJD](https://news.bjd.com.cn/2026/08/26/90090997.shtml) |
| Standing "high jump" 3.40 m, scored as the lowest body point above ground at apex (not a bar clearance) (2025: 0.956 m, RobotEra L7) | Tianzhuo team | 25-26 Aug 2026 | OFFICIAL | CGTN (above) |
| Standing long jump 1.4 m | Unitree G1 (1.32 m tall) | Oct 2024 | CO | [IE](https://interestingengineering.com/innovation/chinas-robot-sets-record-for-longest-standing-jump) |
| Standing long jump 1.4 m; 0.44 m platform | Cassie | RSS 2023 | PR | [PDF](https://hybrid-robotics.berkeley.edu/publications/RSS2023_Cassie_RL_Jumping.pdf) |
| Forward jump 1.5 m | Unitree G1 (ASAP) | RSS 2025 | PR | via ASAP paper |

### 4.3 Hurdles / obstacles

No hurdles race at standard heights was found. The robot games run obstacle races.

| Result | Robot | Date | Status | Source |
|---|---|---|---|---|
| 100 m obstacle race 1:28.32 over 10 obstacles (consecutive hurdles, ramps, spiral stairs, vault platform, crawl tunnel) | AgiBot Lingxi X2, 2026 WHRG | 24 Aug 2026 | OFFICIAL | [BJD](https://news.bjd.com.cn/2026/08/24/11930566.shtml) |
| 100 m obstacle race ("100 m hurdles" in English press) 33.71 s | Unitree G1 (Shanghai Gaoyi team), 2025 WHRG | 16 Aug 2025 | OFFICIAL | [ithome](https://www.ithome.com/0/875/944.htm) |
| Leaps hurdles (sim-trained 0.05-0.5 m; real 0.25 m foam) and 0.8 m gaps, runs at 1.8 m/s | Unitree H1, Humanoid Parkour Learning | CoRL 2024 | PR | [arXiv 2406.10759](https://arxiv.org/abs/2406.10759) |
| Climbs obstacles up to 1.25 m (96% of robot height) | Unitree G1, Perceptive Humanoid Parkour | 17 Feb 2026 | arXiv | [arXiv 2602.15827](https://arxiv.org/abs/2602.15827) |

### 4.4 Bat, racket and striking

**No real humanoid has published numbers for batting a pitched baseball.**

| Result | Robot | Date | Status | Source |
|---|---|---|---|---|
| Baseball: abstract says it bats and catches balls thrown "in excess of 14 m/s" from 7.3 m, and throws at >30 m/s. Body text (read by the research agent, not re-checked): 27/33 hits (>82%), 0.525 s reaction, swinging 2 ms early or late misses. No bat speed reported | AthenaZero (RAI Institute), **fixed-base bimanual arms, not a humanoid** | 15 Sep 2026; *Science Robotics* 11(18), 2026 | PR | [arXiv 2609.19194](https://arxiv.org/abs/2609.19194) |
| Table tennis: 106-shot rally; 96.2% hit, 92.3% return (26 balls); returns in 0.42 s; external mocap | HITTER, Unitree G1 (UC Berkeley) | 28 Aug 2025 | arXiv | [arXiv 2508.21043](https://arxiv.org/abs/2508.21043) |
| Table tennis, onboard vision only: 93.7% contact, 59.7% return (642 launches) | SMASH, Unitree G1 (HKU) | 1 Apr 2026 | arXiv | [arXiv 2604.01158](https://arxiv.org/abs/2604.01158) |
| Badminton: **racket speed at impact 5-8 m/s** (the only humanoid swing speed found); shuttle out up to 19.1 m/s; 91.3% hits | Phybot C1 | v4, 14 Sep 2026 | arXiv | [arXiv 2511.11218](https://arxiv.org/abs/2511.11218) |
| Tennis: real forehand 90.9%, backhand 77.8% in court (96.5% is the sim figure) | LATENT, Unitree G1 | 13 Mar 2026 | arXiv | [arXiv 2603.12686](https://arxiv.org/abs/2603.12686) |

### 4.5 Basketball

| Result | Robot | Date | Status | Source |
|---|---|---|---|---|
| **Dribble 8/10**, jump shot 8/10, layup 7/10, spin 9/10; onboard proprioception only; no consecutive-dribble count | HumanX, real Unitree G1 (HKUST + Shanghai AI Lab) | 2 Feb 2026 | arXiv | [arXiv 2602.02473](https://arxiv.org/abs/2602.02473) |
| "Dribbled three times", 1 free throw made | Toyota CUE7 (219 cm, **wheeled** base) | 12 Apr 2026 | PRESS | [Frontier Beat](https://frontierbeat.com/2026/04/15/toyota-cue7-basketball-robot-reinforcement-learning/) |
| Guinness farthest shot by a humanoid robot, 24.55 m | Toyota CUE6 | 26 Sep 2024 | OFFICIAL | [Guinness](https://www.guinnessworldrecords.com/world-records/768393-farthest-basketball-shot-by-a-humanoid-robot) |
| Guinness 2,020 consecutive free throws | Toyota CUE3 | 17 May 2019 | OFFICIAL | [Toyota](https://global.toyota/en/mobility/frontier-research/41965744.html) |

There was no basketball event at WHRG 2025 or 2026, and no Chinese-company dribbling counts were found (search-limited).

### 4.6 Muscle-actuated robots

| System | Date | Status | Capability |
|---|---|---|---|
| Clone Robotics: hydraulic "Myofiber" (3 g fiber, >=1 kg force, >30% contraction, <50 ms); Protoclone V1 >1,000 fibers, >200 DoF ([site](https://clonerobotics.com/android/)) | Feb 2025; roadmap Apr 2026 | CO | Shown suspended in a rig; **no standing or walking** as of Sep 2026 ("walking by 2027" roadmap). |
| Kenshiro (160 muscles, 64 DoF, 2012), Kengoro (*Science Robotics*, 2016-17), Musashi (2019), U. Tokyo JSK ([IEEE Spectrum](https://spectrum.ieee.org/kenshiro-robot-gets-new-muscles-and-bones)) | 2012-2026 | PR | Tendon-driven; push-ups, badminton hit (Kengoro); **no running or jumping**. |
| Buchner et al., electrohydraulic (HASEL) leg, ETH/MPI-IS ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC11385520/)) | *Nat Commun*, 9 Sep 2024 | PR | 2-DoF, 225 g; jump 128 mm (40% of leg height), takeoff 0.75 m/s; hops at 3 Hz on grass/sand/rock; tethered on a boom. |
| Athlete Robot (Niiyama & Kuniyoshi, U. Tokyo, pneumatic McKibben) ([project](http://www.isi.imi.i.u-tokyo.ac.jp/~niiyama/projects/proj_athlete_en.html)) | 2010-2012 | PR | **Ran 2.42 m/s for five steps**; jumps ~0.5 m. Still the best muscle-actuated running biped found. |

## 5. Human reference numbers for scoring

| Quantity | Value | Source (date) |
|---|---|---|
| 100 m world record | 9.58 s, Usain Bolt, Berlin, 16 Aug 2009 (still the record as of Sep 2026) | [Wikipedia 100 m](https://en.wikipedia.org/wiki/100_metres) |
| Peak sprint speed (Bolt, 9.58 WR) | 12.32 m/s at 52.5 m (laser, Stuhec et al., *Bioengineering* 10(11):1254, 2023); earlier analyses report 12.34 m/s over 70-80 m (Mackala & Mero); ~12.4 m/s is the widely quoted segment figure over 60-80 m | [PMC10669785](https://pmc.ncbi.nlm.nih.gov/articles/PMC10669785/) |
| Bolt stride | 41 steps, mean step ~2.44 m, ~4.28 steps/s (secondary sources; UNVERIFIED against the primary IAAF report) | search summary of biomechanics reports |
| Trained-athlete sprint (non-sprinters) | MLB "Sprint Speed" league average 27 ft/s = 8.2 m/s; 30 ft/s = 9.1 m/s is elite ("Bolt" run) | [MLB Statcast glossary](https://www.mlb.com/glossary/statcast) |
| Recreational preferred running (jogging) speed | 3.0 +/- 0.5 m/s in a recreational-runner biomechanics study (J Biomech 2018, "A little bit faster..."; abstract-level, full text not accessed); free-living preferred speeds ~3.25-3.42 m/s men, 2.74-2.87 m/s women (secondary summary) | [ScienceDirect S0021929018300964](https://www.sciencedirect.com/science/article/pii/S0021929018300964) |
| Long jump world record | Men 8.95 m, Mike Powell, Tokyo, 30 Aug 1991 (still standing Sep 2026); women 7.52 m, Galina Chistyakova, 11 Jun 1988 | [Wikipedia Long jump](https://en.wikipedia.org/wiki/Long_jump) |
| Elite long jump takeoff kinematics | 8.00-8.20 m jumpers: last-step speed 11.44 +/- 0.72 m/s, takeoff Vx 8.63, Vy 3.05 m/s, takeoff angle 20.2 +/- 1.6 deg, board contact 0.110 +/- 0.012 s (Wei, Yuan, Xie, *Front. Physiol.*, May 2026) | [PMC13233344](https://pmc.ncbi.nlm.nih.gov/articles/PMC13233344/) |
| Typical amateur long jump | High-school boys ~4.9-6.1 m (16-20 ft), state qualifiers >6.4 m: coaching-site figures only, no peer-reviewed norm found (UNVERIFIED) | [trackandfieldapp](https://www.trackandfieldapp.com/average-long-jump-distance-by-age/) |
| 110 m hurdles (men) | 10 hurdles, 1.067 m (42 in); 13.72 m to first, 9.14 m between, 14.02 m to finish; sprint hurdlers take 3 steps between hurdles | [Wikipedia 110 m hurdles](https://en.wikipedia.org/wiki/110_metres_hurdles), [World Athletics](https://worldathletics.org/disciplines/hurdles/110-metres-hurdles) |
| 110 m hurdles WR | 12.75 s (+1.0 m/s), Ja'Kobe Tharp, NCAA Championships semifinal, Eugene, 10 Jun 2026, **pending ratification** at time of reports (previous: Aries Merritt 12.80, 7 Sep 2012). Le'Ezra Brown's 12.72 on 9 Aug 2026 is a **U20** record over 0.991 m hurdles, not the senior WR | [CBC](https://www.cbc.ca/sports/olympics/summer/athletics/ja-kobe-tharp-hurdles-world-record-ncaa-championships-9.7231586), [World Athletics U20](https://worldathletics.org/competitions/world-athletics-u20-championships/oregon26/news/report/day-four-evening-mixed-track-oregon-26) |
| 100 m hurdles (women) | 0.838 m (33 in); 13 m to first, 8.5 m between, 10.5 m to finish. WR 12.09 s (0.0 wind), Masai Russell, Zurich, 27 Aug 2026 (previous 12.12 Amusan 2022) | [Wikipedia 100 m hurdles](https://en.wikipedia.org/wiki/100_metres_hurdles), [Olympics.com](https://www.olympics.com/en/news/masai-russell-100m-hurdles-world-record-zurich) |
| 400 m hurdles | Men 0.914 m (36 in), women 0.762 m (30 in); 45 m to first, 35 m spacing, 40 m to finish. WR men 45.80 s, Alison dos Santos, Zurich, 27 Aug 2026 (previous 45.94 Warholm 2021); women 50.37 s, Sydney McLaughlin-Levrone, Saint-Denis, 8 Aug 2024 | [Wikipedia 400 m hurdles](https://en.wikipedia.org/wiki/400_metres_hurdles), [Olympics.com](https://www.olympics.com/en/news/zurich-2026-mens-400m-hurdles-dos-santos-world-record) |
| MLB bat speed | League average 71.5 mph (32.0 m/s) in 2024 (71.6 mph for 2023 post-ASB); measured 6 in from the bat head ("sweet spot"), average of a player's top 90% of swings; "fast swing" >= 75 mph (33.5 m/s). Top 2024 averages: Stanton 80.6, O. Cruz 77.7 mph; lowest qualified Arraez 62.4 mph | [Savant bat-speed page](https://baseballsavant.mlb.com/visuals/bat-speed-distribution), [NBC DFW, 13 May 2024](https://www.nbcdfw.com/news/sports/mlb/mlb-tracking-data-statcast-bat-speed-swing-length-blasts/3539430/) |
| MLB swing geometry (2025 metrics) | Swing length avg ~7.3 ft (range ~6 to >8.5 ft). On hard-hit middle-middle four-seamers: 73.6 mph, 7.2 ft, attack angle 8 deg, swing-path tilt 32 deg; low curveballs: 73.7 mph, 7.6 ft, 9 deg, 37 deg (new metrics released May 2025) | [FanGraphs, 21 May 2025](https://blogs.fangraphs.com/test-driving-statcasts-newest-bat-tracking-metrics/) |
| Swing timing | "Time to contact" (downswing start to impact) pro/MLB average 0.149 s, range 0.13-0.17 s (Blast Motion vendor benchmark, page dated 27 Aug 2026; not peer-reviewed); a big-league fastball reaches the plate in ~0.4 s | [Blast Motion](https://blastmotion.com/blog/what-is-time-to-contact-in-baseball/) |
| Basketball (FIBA 2024 rules) | Size 7: circumference 750-770 mm, mass 580-620 g; dropped from ~1,800 mm (underside) must rebound to 1,035-1,085 mm (underside) (i.e. restitution ~0.76-0.78); ring top 3,050 mm | [FIBA Official Basketball Rules 2024, Equipment §2.4](https://assets.fiba.basketball/image/upload/documents-corporate-fiba-official-rules-2024-official-basketball-rules-and-basketball-equipment.pdf) |
| Dribble frequency | 1.34-1.38 Hz (+/- 0.07-0.13) for 23 novices dribbling while walking a slalom at 0.87 and 1.75 m/s (Carius et al., PLoS ONE 15(9):e0238318, 2020). No peer-reviewed expert-frequency figure found (UNVERIFIED for experts) | [PMC7470377](https://pmc.ncbi.nlm.nih.gov/articles/PMC7470377/) |
| Dribble height | "High static dribble" = ball bounced up to **waist height** (Park & Jeong, IJERPH 2023; experts more consistent in A-P direction, radial accuracy not different from novices). Numeric apex height not reported; waist height of an adult is ~0.9-1.1 m (estimate) | [PMC10218343](https://pmc.ncbi.nlm.nih.gov/articles/PMC10218343/) |

## 6. Comparison table template

For each skill, fill in the "Ours" column. Each cell gives the number, then the source and date. Keep the columns separate: muscle-only, any actuation, real hardware, human.

| Skill (primary metric) | Ours | Best simulated, muscle-driven | Best simulated, any actuation | Best real robot | Human reference |
|---|---|---|---|---|---|
| **Running** (steady and peak speed, m/s; 100 m time) | | **12.5 +/- 0.5 m/s peak, 100 m ~10 s**, 136 MTUs, no assist, max force x2 (Wang et al., arXiv 2609.11083, Sep 2026, preprint). Peer-reviewed MuJoCo: **MyoLeg 5.44 m/s**; H2190/Hyfydy 6.49 m/s (Schumacher et al., *iScience* 2025). Trajectory optimization: 11.85 m/s for one step, with reserve actuators (Haralabidis, *MSSE* 2025) | Same as muscle-driven (12.5 m/s). Torque/PD characters: ~7 m/s (ASE, SIGGRAPH 2022). Tracking: PHC+ 99.2% AMASS test, 36.1 mm (ICLR 2024) | **100 m 8.64 s** (~11.6 m/s average), Tiangong Ultra, WHRG, 26 Aug 2026 (OFFICIAL). Claimed peaks: 14.5 m/s Honor Lightning (PRESS), 12.66 m/s Unitree (CO). Muscle hardware: 2.42 m/s, Athlete Robot (2010-12) | 100 m WR 9.58 s; peak 12.32 m/s (Bolt 2009; laser, Stuhec 2023). Recreational preferred running speed 3.0 +/- 0.5 m/s. MLB sprint average 8.2 m/s |
| **Bat swing** (bat sweet-spot speed at contact; hit/contact rate on varied pitches; timing and spatial intercept error) | | **None found.** Nearest muscle-driven strike: table tennis 80.3% success / 95.1% hit, with 2 pelvis actuators (Diff-Muscle, arXiv 2603.08617, Mar 2026). MyoChallenge 2025 winner: 64% | **No baseball batting found.** Tennis: hit rate 0.92 median with residual forces, 0.78 average without (Vid2Player3D, SIGGRAPH 2023). G1 tennis in sim: 96.52% (LATENT 2026) | **No humanoid batting found.** Fixed-base arms: bats balls pitched >14 m/s from 7.3 m, 27/33 hits (AthenaZero, *Sci Robot* 2026). Humanoid racket speed at impact 5-8 m/s (Phybot C1 badminton, arXiv 2026) | MLB average bat speed 71.5 mph = 32.0 m/s (2024); "fast" >= 75 mph = 33.5 m/s; Stanton 80.6 mph. Time to contact 0.149 s (Blast Motion, vendor). Fastball reaches the plate in ~0.4 s |
| **Dribbling** (Hz; ball apex height; consecutive dribbles without loss; success over N trials; locomotion speed while dribbling) | | **None found.** Nearest muscle-driven ball skill: Baoding balls 0.55 (MyoChallenge 2022) | Crossovers 95.7-99.6% over 1000 transitions; running dribble cycle 0.6 s (Liu & Hodgins, SIGGRAPH 2018). Dribble 97.7-99.1% (SkillMimic-V2, SIGGRAPH 2025). Dribbling at 0-5 m/s, 98.3% catch (Learning to Ball, SIGGRAPH Asia 2025) | **Dribble 8/10** trials, real Unitree G1 (HumanX, arXiv Feb 2026). No published consecutive-dribble count for a legged humanoid; CUE7 (wheeled) dribbled 3 times (Apr 2026) | Novices walking: 1.35 Hz (Carius, *PLoS ONE* 2020). "High dribble" = waist height (Park & Jeong 2023). FIBA ball: 580-620 g; 1.8 m drop rebounds to 1.035-1.085 m |
| **Long jump** (distance from takeoff line; approach speed at the last step; takeoff angle; landing without fall) | | **None found** (running long jump). Nearest: "run jump" imitation, 700 muscles (MS-Emulator, arXiv 2603.29332, 2026); standing vertical jump, hand reach 2.85 m (Wang 2026) | RL character: **5.105 m**, 100% success (SMPLOlympics PULSE, 2024). Torque trajectory optimization: **9.86 m** (Emonds et al., arXiv 2608.22507, Aug 2026). High jump: 2.00 m Fosbury flop (Yin et al., SIGGRAPH 2021) | **7.97 m** run-up, Tiangong Ultra, WHRG, 23 Aug 2026 (OFFICIAL; rules not verified). Standing: 4.83 m (26 Aug 2026) | WR 8.95 m (Powell 1991). Elite (8.0-8.2 m): last-step speed 11.4 m/s, takeoff 20 deg, board contact 0.11 s (*Front Physiol* 2026). Amateur: high-school boys ~4.9-6.1 m (UNVERIFIED) |
| **Hurdling** (time over N hurdles at stated height; hurdles knocked; steps between hurdles; clearance margin) | | ~**15.0 s for 110 m over 0.7-1.0 m hurdles**, poor technique (Wang 2026, preprint). No regulation-height muscle-driven result | **17.76 s for 110 m over 10 x 1.067 m hurdles, 100% success** (SMPLOlympics PULSE, PD, 2024) | No standard-hurdle race. Obstacle course: 100 m in 1:28.32 (AgiBot Lingxi X2, WHRG 2026); 33.71 s (Unitree G1, 2025). Real 0.25 m foam hurdles at 1.8 m/s (Unitree H1, CoRL 2024) | 110 mH WR 12.75 s over 1.067 m (Tharp, 10 Jun 2026, pending ratification); 100 mH 12.09 s over 0.838 m (Russell 2026); 400 mH 45.80 s / 50.37 s over 0.914 / 0.762 m. 3 steps between sprint hurdles |

## 7. What to report so the results are comparable

**Actuation disclosure** (the most common source of non-comparable claims):
- Muscle count and model: the MyoSuite model name and version, or the MTU count.
- Tendon model: rigid in MuJoCo.
- Any strength scaling: Fmax multiplier.
- Every non-muscle actuator: pelvis or root residual forces, reserve or arm torque motors, position actuators, and training-only assist forces.
- Simulator and timestep; control rate; chunk decision rate (decisions per second or per gait cycle).
- A "no assist" claim must be literally true, as it is in Wang 2026, KINESIS and Schumacher 2025.

**Per-skill primary metrics**, in the units the comparators use:
- **Running:**
  - Peak speed, and steady speed averaged over >= 10 strides (m/s).
  - 100 m time from a standing start.
  - Cadence (steps/min), step length, and ground contact / flight time.
  - Survival or falls per 100 m.
  - Joint-angle error or correlation against treadmill data at a matched speed: Fukuchi treadmill running data at 2.5-4.5 m/s, as Lambda-Hold uses.
  - Peak vertical GRF in body weights. Wang 2026 is ~2 BW too high, so this is a known weakness to beat.
- **Bat swing:**
  - Bat speed measured 6 in (15 cm) from the barrel tip at contact, to match Statcast.
  - Time to contact, from downswing start.
  - Swing length (ft or m of bat-head path).
  - Attack angle.
  - Contact rate, and spatial intercept error (cm) at the bat-ball closest approach, over a distribution of pitch speeds and locations. Include late re-aims: say how many ms before contact the prediction changed.
  - Exit velocity, if the ball is simulated.
- **Dribbling:**
  - Frequency (Hz) and ball apex height (m, relative to waist).
  - Consecutive dribbles until loss (median and max over N >= 100 trials).
  - Success per move (crossover, between-legs) over 1,000 transitions, as Liu & Hodgins report.
  - Dribbling while locomoting at a stated m/s.
  - The ball's restitution calibrated to FIBA (1.8 m drop, 1.035-1.085 m rebound).
- **Long jump:**
  - Official-style distance: takeoff line to nearest landing mark.
  - Approach speed at the last step; takeoff angle and board contact time.
  - Takeoff foul rate and landing-without-fall rate.
  - Distance vs approach speed, since "distance is limited by run-up speed" (Yin 2021).
- **Hurdling:**
  - Hurdle height, which must be stated: regulation 1.067 / 0.991 / 0.914 / 0.838 / 0.762 m.
  - Time over 110 m or 10 hurdles; hurdles knocked; steps between hurdles (3 is elite).
  - CoM clearance margin over the bar, since Wang 2026 clears "unnecessarily high".
  - Success rate over N runs.

**Cross-cutting metrics:**
- Success rate over >= 100 seeded trials with perturbations: pushes in N, terrain noise, ball-trajectory noise.
- Effort: mean squared activation, as the MyoChallenge effort term uses, and/or a metabolic model.
- Human-likeness:
  - Joint-angle RMSE (deg) or correlation vs mocap.
  - EMG correlation per muscle group, as Lambda-Hold reports.
- Correction latency: sensor event to first corrective muscle change (ms). Compare against human visuomotor latency, ~100-150 ms.
- Training compute: steps, wall-clock and GPU, because Lambda-Hold (1 h) and Wang 2026 (hours) set a low bar.
- Video of every reported number.

## 8. Discrepancies and unverified items

- **Tiangong Ultra 100 m:** reported as 9.39 s (22 Aug), 8.86 s (25 Aug) and 8.64 s (26 Aug, final). Use 8.64 s (CGTN / Global Times). Whether it ran autonomously in the final is not stated in CGTN; Wikipedia says 2026 sprints required autonomy (UNVERIFIED).
- **Robot long jump 7.97 m:** Bastille Post dates it Sunday 24 Aug, but 24 Aug 2026 is a Monday, so it was likely 23 Aug. The run-up length and measurement rules were not verified.
- **2026 robot 1500 m (2:21.64):** faster average speed than the 400 m (38.15 s) as reported. Treat with caution.
- **Honor Lightning 14.5 m/s** and **Unitree "Superman" 12.66 m/s:** single-source press or company claims.
- **Wikipedia's 110 mH page** lists Le'Ezra Brown's 12.72 s as the world record. That mark is the U20 record over 0.991 m hurdles (World Athletics, 9 Aug 2026). Senior WR: Tharp 12.75 s, pending ratification.
- **MyoLeg DoF:** reported as 16, 20, 28 or 29 depending on the source. Cite the model version you use.
- **Lee et al. 2019 muscle count:** 284-346 depending on foot model; the often-quoted 326 was not found in the paper.
- **SMPLOlympics:** its high-jump "Height" column (2.01 m PULSE, 4.08 m PPO) is undefined in the text. PPO's 19.42 m long jump is an exploit.
- **Human preferred-running speed (3.0 +/- 0.5 m/s):** full text not accessed. Amateur long-jump norms come from coaching sites only. Expert dribble frequency: no peer-reviewed figure found.
- **Not searched to completion:** SIGGRAPH/CVPR 2026 proceedings; Chinese-company dribbling demos; the MIT humanoid; Unitree H1-2 / R1 speeds; 2025-2026 artificial-muscle legs beyond HASEL.
