    n_trials = len(TRIALS)
    n_champs = len(CHAMPS)
    streak_max = int(max(scores_ok("dribble_btl_streak_25")))
    btl_any = sum(1 for x in scores_ok("dribble_btl_streak_25") if x >= 1)
    btl_two = sum(1 for x in scores_ok("dribble_btl_streak_25") if x >= 2)
    btl_n = len(scores_ok("dribble_btl_streak_25"))

    # ------------------------------------------------------------ board -------------
    board_items = [
        ("run-natural", "Natural running", "done", "7.3° from human running, 12 starts"),
        ("sprint", "Sprint", "run", f"{V('sprint_top_speed_p95')} m/s, 95th pct."),
        ("blocks", "Sprint from blocks", "done", f"30 m in {V('sprint_blocks_30')} s · Bolt 3.78"),
        ("longjump", "Long jump", "run", f"4.90 m best · {V('long_jump_p95_robust')} m robust"),
        ("standing", "Standing jump", "done", f"{V('search_jump_legal', 3)} m legal"),
        ("hurdles", "Hurdles", "stuck", "0.762 m: 4 of 8 clear hurdle 1"),
        ("bat", "Baseball swing", "run", "21.6 m/s, reflexes on, athlete body"),
        ("dribble", "Dribble", "run", f"through the legs: mean streak {V('dribble_btl_streak_25', 2)}, max {streak_max}"),
        ("tt", "Table tennis", "stuck", f"P2 {100 * F('tt_p2_300'):.0f}% · P1 100%"),
        ("balance", "One-leg balance", "run", "12 of 20 hold 5 minutes"),
        ("soccer", "Penalty kick", "stuck", "P1 100% · P2 0%"),
        ("relocate", "Relocate", "scored", f"{V('relocate_p2eval_official', 3)} on the eval env"),
        ("chase", "Chase tag", "scored", f"P1 {V('chase_p1', 2)} · P2 {V('chase_p2', 2)} (winner 0.666)"),
        ("walk", "Walking", "scored", f"{V('walk_stride', 2)} m steps at 1.45 m/s"),
        ("baoding", "Baoding balls", "scored", f"{V('baoding_p2', 3)} (winner 0.55)"),
        ("die", "Die and bimanual", "stuck", "no full solves yet"),
    ]
    board = "".join(
        f'<a class="slot" href="#{i}"><span class="name">{e(n)}</span>{chip(k)}<span class="num">{e(t)}</span></a>'
        for i, n, k, t in board_items)

    # ------------------------------------------------------------ goals -------------
    goals = table(
        ["Goal", "Best now", "Compared with", "What stands in the way"],
        [
            ["Increase the bat speed",
             "21.6 m/s on 24 unseen pitches with reflexes on (was 13.9), on the athlete body. 25.2 m/s as an open-loop ceiling study, which holds the trials.",
             "MLB average about 32 m/s",
             "The reflex-on swing reaches 82–85% of the ceiling swing. The trunk turns at 51–60% of MLB rates and elbow extension at 38–39%."],
            ["Dribble through the legs",
             f"Arena, 25 starts: mean longest streak {V('dribble_btl_streak_25', 2)} in 15 s, at most {streak_max}; at least one good pass on {btl_any} of {btl_n}. The video shows a streak of 3 on a start found by scanning seeds.",
             "Target: several in a row",
             "The receiving hand cannot take a fast, flat ball and relaunch it high; the arms lag the plan."],
            ["Exceed 10 m/s in the sprint",
             f"{V('sprint_top_speed_p95')} m/s (95th-percentile body, v3). The first runner on the calibrated v4 body (average) is in the arena at {V('sprint_top_speed_v4')} m/s.",
             "Ceiling with perfect control on v4: 10.45 (95th pct.). Recreationally active adults 7.8, trained sprinters 9.9.",
             "Only the average body has a v4 runner so far. 10 m/s needs 96% of the 95th-percentile v4 ceiling."],
            ["Long jump with the best runner, then beyond human",
             f"4.90 m on one start, the start its take-off was designed from (95th-percentile body, 7.02 m/s runner). Over 16 perturbed starts: {V('long_jump_p95_robust')} m (95th pct., 6.94 m/s runner), {V('long_jump_elite2_robust')} m (elite), {V('long_jump_robust')} m (average). The jumper flips over after landing; the mark is legal.",
             "Untrained men 4.95 m, high-school qualifiers 6.07–6.65 m, world record 8.95 m",
             "In a landing search on a program not yet entered, 3 of 32 captured take-offs roll over and 2 foul (a timing problem, diagnosed 01:30). The ideal take-off from the 7.02 m/s runner's approach reaches 4.93 m."],
            ["Table tennis phase 2 above 90%",
             f"{100 * F('tt_p2_300'):.0f}% over 300 serves ({100 * F('tt_p2'):.0f}% over 100)",
             "Winner 64% (2025); 80.3% in a Mar 2026 preprint",
             "The paddle face follows 53 to 66% of an aimed change on the forehand and 13 to 28% on the backhand. Live arm tracking fixed the reach, but the tracked arm plays like a new player and needs a long practice run."],
            ["Balance five minutes on one leg",
             "12 of 20 fresh stances hold at least 300 s (strict 310 s trial). A version with a tuned lift holds 15 of 20 (p 0.23, not promoted).",
             "Target: 300 s",
             "On the 20 starts every failure was at the lift. On 40 new starts 5 fail within 20 s: 1 in the lift, 1 in the set, 3 in the hold after it."],
            ["Score all the soccer goals",
             "Phase 1 100%. Phase 2 0 of 100.",
             "2025 winner 32% on phase 2",
             "The kick fails from a settled stance, and this body cannot walk upright: its spine folds."],
            ["Improve robolab",
             f"{n_trials} arena trials ({n_champs} with a champion), a calibrated v4 body, a MyoSuite relocate bug found, two compiler fixes being merged.",
             "–",
             "See what is running, near the end."],
        ], wide=True)

    # ------------------------------------------------------------ charts ------------
    ch_sprint = chart(
        "c-sprint", "Sprint speed", "m/s", 15, [0, 3, 6, 9, 12],
        [
            dict(label="Average body", sub="best on the v3 body", value=F("sprint_top_speed"), ceiling=8.2, kind="ours",
                 tip="Ceiling with perfect control and a free torso: 6.89 on the v3 body, 8.2 on v4. A first v4 runner is in the arena at 4.65."),
            dict(label="95th percentile", sub="best on the v3 body", value=F("sprint_top_speed_p95"), ceiling=10.45, kind="ours",
                 tip="Ceiling with perfect control and a free torso: 9.69 on the v3 body, 10.45 on v4."),
            dict(label="Elite, literature", sub="best on the v3 body", value=F("sprint_top_speed_elite2"), ceiling=9.28, kind="ours",
                 tip="Ceiling: 8.5 on the v3 body, 9.28 on v4. Every part of this profile is cited; its knee and ankle extensors sit near the untrained mean."),
            dict(label="Recreationally active adults", sub="reference", value=7.8, kind="ref",
                 tip="7.3–8.3 m/s: Lazarczuk et al. 2025 (7.77 ± 0.86, mixed group) and Clark, Meng & Stearne 2020 (8.23)"),
            dict(label="Trained sprinters", sub="reference", value=9.9, kind="ref", tip="9.90 ± 0.46 m/s, 79 sprinters (Miyashiro et al. 2019)"),
            dict(label="Usain Bolt", sub="reference", value=12.34, kind="ref",
                 tip="12.34 m/s over 60–80 m of his 9.58 s run (Mackala & Mero 2013). Elite sprinters run 11.5–12.3 m/s."),
        ],
        "Bars are the arena champions on the v3 bodies. Outlines are the ideal-control ceiling with the torso free on the calibrated v4 body (the v3 ceilings are in each row's note). An earlier 10.2 m/s ceiling rested on an ideal torso stabiliser and is not used.",
        target=dict(v=10, label="Goal 10 m/s"))

    ch_jump = chart(
        "c-jump", "Long jump", "m", 10, [0, 2, 4, 6, 8, 10],
        [
            dict(label="Average body", sub="16 perturbed starts", value=F("long_jump_robust"), kind="ours", tip="One-start best 2.47 m."),
            dict(label="95th pct., 16 starts", sub="6.94 m/s runner", value=F("long_jump_p95_robust"), ceiling=4.61, kind="ours",
                 tip="Ceiling 4.61 m is the ideal take-off from this runner's own approach."),
            dict(label="95th pct., one start", sub="7.02 m/s runner", value=F("long_jump_p95"), ceiling=4.93, kind="ours",
                 tip="The start its take-off was designed from (ideal take-off 4.93 m). The jumper flips over after landing; the mark is legal."),
            dict(label="Elite, literature", sub="16 perturbed starts", value=F("long_jump_elite2_robust"), ceiling=4.25, kind="ours",
                 tip="One-start champion 4.01 m. Ceiling 4.25 m from its 6.6 m/s approach."),
            dict(label="Elite, old profile", sub="16 starts, provisional", value=F("long_jump_elite_robust"), kind="ours",
                 tip="Uses the elite profile whose muscle strengths were set too high, with the older take-off practice."),
            dict(label="Untrained women", sub="reference", value=3.57, kind="ref", tip="3.57 ± 0.54 m (Romdhani et al. 2026)"),
            dict(label="Untrained men", sub="reference", value=4.95, kind="ref", tip="4.95 ± 0.55 m (Romdhani et al. 2026)"),
            dict(label="High-school qualifying", sub="reference", value=6.36, kind="ref",
                 tip="Boys 6.07–6.65 m (Oregon 2026 state standards). Jumpers aged 14–28 run up at 8.89 m/s (Bayraktar & Cilli 2018)."),
            dict(label="College finals", sub="reference", value=7.66, kind="ref", tip="NCAA D1 finals medians 7.56–7.75 m"),
            dict(label="World record", sub="reference", value=8.95, kind="ref", tip="Powell 1991; run-up 11.0 m/s"),
        ],
        "Bars are means over the arena starts (16 perturbed starts, or the single nominal start). Outlines are the ideal-control take-off ceiling for that runner's own approach.")

    ch_bat = chart(
        "c-bat", "Bat speed at contact", "m/s", 40, [0, 10, 20, 30],
        [
            dict(label="Hitch-free swing (v5)", sub="before", value=13.86, kind="ours", tip="24 pitches it never saw. Its arm drive was limited by its plan."),
            dict(label="Codex pure search", sub="independent", value=14.79, kind="ours", tip="Keeps the pause before and after contact."),
            dict(label="Contraction knots", sub="latest, not a champion", value=21.57, kind="ours",
                 tip="Knots distilled from the fast swing, reflexes on. 2–4 of 24 pitches missed; the re-tuned variant scored 20.63. It lost the trial to the open-loop program."),
            dict(label="Open-loop program", sub="ceiling study", value=25.24, kind="study",
                 tip="Excitation program, reflexes off. 24 of 24 hits. Built from 6 of the 18 grid pitches; the 24 fresh pitches are held out."),
            dict(label="MLB average", sub="reference", value=32.0, kind="ref", tip="About 72 mph at the sweet spot (Savant 2024)"),
        ],
        "Athlete body (strength ×1.5, pivot root). All bars are scored on 24 fresh pitches that no swing was trained on.",
        legend_ours="Swing with reflexes on")

    ch_tt = chart(
        "c-tt", "Table tennis, phase 2", "%", 100, [0, 25, 50, 75, 100],
        [
            dict(label="Robolab, all serves", sub="300 serves", value=round(100 * F("tt_p2_300"), 1), kind="ours",
                 tip="Forehand serves 36–46%, backhand serves 23%."),
            dict(label="Robolab, backhand serves", sub="131 serves", value=round(100 * F("tt_p2_backhand"), 1), kind="ours",
                 tip="The backhand works, but weakly."),
            dict(label="Challenge winner", sub="reference", value=64, kind="ref", tip="2025 MyoChallenge phase 2"),
            dict(label="Best reported", sub="reference, preprint", value=80.3, kind="ref",
                 tip="Diff-Muscle (Zhao et al., arXiv 2603.08617, Mar 2026), a preprint; up to 14 dual-agent rally exchanges."),
        ],
        "MyoChallenge phase-2 success rate: the share of serves the task scores as solved.",
        target=dict(v=90, label="Goal 90%"))

    charts = f'<div class="chartgrid">{ch_sprint}{ch_jump}{ch_bat}{ch_tt}</div>'

    # ------------------------------------------------------------ ability cards -----
    run_cards = [
        card("run-natural", "Natural running from human keyframes", [chip("done", "Champion, 12 starts")],
             [vid("run_knots.mp4", out("run_knots.mp4"), "Natural runner with the literature curves ghosted",
                  "12 s of the current runner. The literature gait curves are ghosted at the current stride phase.")],
             ["Contraction keyframes at touchdown, mid-stance and toe-off from human running data, eased through and latched on the feet. The latest version adds a knot at each gait event (a contraction, a velocity and an acceleration for every muscle), fitted to the target by least squares and then improved from stride-by-stride error curves (iterative learning control).",
              "Against the literature curves it is now **7.3°** from human running on the 12-start trial: 11 of 12 starts stay up (the old runner also falls on one), and the 11 that stay up are all better than before. On the harder 48-start trial it is 7.2° on the starts that stay up, with 13 falls against 17, which is not significant. Against motion-capture running (Fukuchi 2017) it is 10.1° and falls on 11 of 48 fresh starts where the earlier runner fell on 17. Against your keyframe set 3, the keyframe-chunk runner falls on 1 of 48 fresh starts without the heel-rise keyframe at 30% of the stride (6 with it), with the pose 2.2° further from your set."],
             table(["Target (fresh starts, paired p)", "Before", "Now"],
                   [["Literature curves (12, p 0.0005)", "#1 fall, 9.13°", "#1 fall, 7.29°"],
                    ["Literature curves, harder trial (48, p 0.17, not promoted)", "#17 falls, 9.22°", "#13 falls, 7.22°"],
                    ["Motion capture (48, p 0.0498)", "#17 falls, 11.0°", "#11 falls, 10.09°"],
                    ["Your set 3, champion change (48, p 0.0095)", "#9 falls, 17.56°", "#1 fall, 19.78°"]]),
             "Train the small learned correction (a convolutional network on proprioception) for the literature and set-3 runners, where the knots alone fall on 8 and 7 of 48 held-out starts. On the mocap runner it cut held-out falls from 14 to 4 of 48 at its best checkpoint (7 at the last).",
             body="v2 anatomy, average adult."),
        card("sprint", "Sprint", [chip("run"), chip("study", "v4: average body in")],
             [vid("sprint_p95_ri.mp4", out("sprint_p95_ri.mp4"), "Sprinter on the 95th-percentile body, 7 m/s",
                  "The champion on the 95th-percentile body from a standing start.")],
             [f"Full drive on the prime movers, with the opposing muscles scaled down as their partners fire (reciprocal inhibition, k 0.5), latched on each foot. **{V('sprint_top_speed_p95')} m/s** on the 95th-percentile body, {V('sprint_top_speed_elite2')} on the literature elite body, {V('sprint_top_speed')} on the average body. The inhibition is worth +0.12 m/s on every start, and without it the gait falls in 4.4 to 5.6 seconds.",
              "An earlier ceiling of about 10.2 m/s for the 95th-percentile body rested on an ideal torso stabiliser that applies up to 3.9 kN·m in a 0.12 s stance, where the stance hip's muscles give at most 185 N·m. Ceilings are now computed with the torso free. On the original body that put the average runner's ceiling at 6.89 m/s, below the 7.8 of recreationally active adults, so the body model was calibrated against published data (the v4 body, below). On v4 the ceilings are 8.2, 10.45 and 9.28 m/s.",
              f"The first v4 runner (average body) is in the arena at **{V('sprint_top_speed_v4')} m/s** on {passes('sprint_top_speed_v4')} starts, {100 * F('sprint_top_speed_v4') / 8.2:.0f}% of its ceiling. It lands on a nearly straight leg, and on some starts it settles into a slower gait."],
             table(["Body", "Best on v3", "v3 ceiling", "v4 runner", "v4 ceiling"],
                   [["Average", f"#{V('sprint_top_speed')}", "#6.89", f"#{V('sprint_top_speed_v4')}", "#8.2"],
                    ["95th percentile", f"#{V('sprint_top_speed_p95')}", "#9.69", "#" + (V('sprint_top_speed_v4_p95') if scores_ok('sprint_top_speed_v4_p95') else "–"), "#10.45"],
                    ["Elite, literature", f"#{V('sprint_top_speed_elite2')}", "#8.5", "#" + (V('sprint_top_speed_v4_elite2') if scores_ok('sprint_top_speed_v4_elite2') else "–"), "#9.28"]]),
             "Move the v4 runner's stance toward the ideal one, then enter the 95th-percentile and elite bodies (the sprint agent's log already has candidates for both that are not in the arena yet). 10 m/s on v4 needs 96% of the 95th-percentile ceiling.",
             body="Average, 95th percentile and literature elite bodies on the v3 anatomy; the calibrated v4 body for the new runner."),
        card("blocks", "Sprint from blocks, keyframed on Usain Bolt", [chip("done", "Champion"), chip("study", "About 2x Bolt's time")],
             [vid("sprint_blocks.mp4", out("sprint_blocks.mp4"), "Start from blocks with Bolt's pose ghosted",
                  "Bolt's pose is ghosted over the runner. No broadcast frames are shown.")],
             ["Keyframes measured from side-view footage of Bolt at block exit, the first steps and the max-velocity cycle. The set position is the mean of the 2018 World Indoor 60 m finalists, and steps 3 to 10 are interpolated. The runner sets on two angled pads, pushes off the rear pad on its force, then the front pad, then accelerates through steps blended from Bolt's first steps into his max-velocity cycle. Reaction time is 0.237 s.",
              f"On the 95th-percentile body it covers 30 m in **{V('sprint_blocks_30')} s** and 100 m in **{V('sprint_blocks_100')} s** on 11 of 12 arena starts. Bolt ran 3.78 s and 9.58 s, so this is about twice his time and 4 to 6 s behind a recreational sprinter: 3.3 steps a second of 1.7 m against his 4.5 of 2.4 to 2.7 m. The same controller on the average body falls on every start. At touchdown its trunk leans about 30° more than Bolt's upright 4°."],
             None,
             "Reuse this start for the hurdler, and move it to the v4 body once a v4 sprinter exists.",
             body="95th-percentile body only: the average body cannot leave the blocks."),
        card("touch", "Touch-only sprint", [chip("done", "Champion, fast-running trial")],
             [vid("sprint_touch.mp4", out("sprint_touch.mp4"), "Sprint from a single touchdown keyframe", "Muscles are tinted by activation.")],
             ["Your idea of keyframing only the toe-touch. One right-touchdown keyframe (the left is its mirror), each stride one spline from touch to touch, with the joint velocities at the touch, and full-power bursts timed on each leg's own touchdown and toe-off. Without the velocities every version fell within two steps.",
              "It took over the fast-running trial (a naturalness score at 5 m/s): 10 of 12 starts stay up where the old champion failed all 12. The quadriceps pulse at landing alone is worth 0.7 m/s. It runs 4.6 m/s on the average body against 5.0 for the tuned sprinter."],
             None, None,
             body="v3 anatomy, average adult."),
    ]

    jump_cards = [
        card("longjump", "Long jump", [chip("run")],
             [vid("long_jump_v5_p95.mp4", out("long_jump_v5_p95.mp4"), "Long jump on the 95th-percentile body, 4.9 m",
                  "The one-start champion: 4.895 m, the start its take-off was designed from. The mark is the left foot and is legal, but the jumper flips over after landing. Take-off, flight and landing play at quarter speed.")],
             ["The run-up is the sprint champion itself. World Athletics rules are in the score: foul line on every tick of the stance, no somersault past 120° until landing is over, no touching the runway after landing, and the mark is the nearest break in the sand by any body part. The take-off comes from an ideal-control analysis of the runner's own approach, distilled into contraction knots latched on the plant touchdown.",
              f"That took the 95th-percentile body from 3.68 to **4.895 m** on one start (99% of that start's 4.93 m ideal take-off; the 7.02 m/s runner) and from 3.22 to **{V('long_jump_p95_robust')} m** on 16 perturbed starts (a slightly slower 6.94 m/s runner, ideal take-off 4.61 m). The average body reaches {V('long_jump_robust')} m robust and 2.47 m on one start."],
             table(["Body", "One start", "16 starts", "Ideal take-off"],
                   [["Average", "#2.47", f"#{V('long_jump_robust')}", "#–"],
                    ["95th percentile", f"#{V('long_jump_p95', 3)}", f"#{V('long_jump_p95_robust')}", "#4.93 / 4.61"],
                    ["Elite, literature", f"#{V('long_jump_elite2')}", f"#{V('long_jump_elite2_robust')}", "#4.25"],
                    ["Elite, old profile (provisional)", f"#{V('long_jump_elite')}", f"#{V('long_jump_elite_robust')}", "#–"]]),
             "Enter the landing program that fixes the roll-overs (a fixed-time landing timing problem, diagnosed at 01:30), then build the same jump on a v4 sprinter. Landings in the search already reach marks up to 4.98 m, so 4.95 is not a hard ceiling.",
             body="v3 anatomy, 95th percentile (elite variants: elite and elite2 profiles)."),
        card("standing", "Standing broad jump", [chip("done"), chip("study", "Codex policy")],
             [vid("codex_standing_jump.mp4", CODEX + "competitor_jump_round2__video_search_jump_legal_tcn.mp4", "Standing jump champion, 1.363 m",
                  "Codex's champion for the legal-distance trial: it lands and stays on its feet.")],
             [f"Contraction keyframes with take-off and landing latched on the centre of mass. The legal-distance champion is Codex's temporal recovery policy at **{V('search_jump_legal', 3)} m** (8 starts): a small learned correction after landing that keeps the jumper on its feet. On 32 larger nudges the champion is our convolutional keyframe policy: **{V('search_jump_robust_legal', 3)} m** with 32 of 32 landing, at the arena's 3 s horizon.",
              "On Codex's own fresh starts our policy is legal at 3 s on 64 of 64 but at 8 s on 0 of 64, while Codex's newer robustness policy (1.3397 m) is legal at 8 s on 57 of 64. That policy is being run in this arena now."],
             None, None,
             body="Planar v3 body."),
        card("hurdles", "Hurdles", [chip("stuck", "Waiting on run-up")],
             [vid("hurdle_hs_076.mp4", out("hurdle_hs_076.mp4"), "Hurdler at 0.762 m", "Hurdle height 0.762 m (2 ft 6 in).")],
             ["Lead knee driven up and extended over the bar, the trail leg lifted out to the side and turned so the knee comes around. At your high-school height of 0.991 m the lead leg clears and the trail leg catches the bar at the first hurdle, so nothing is cleared. At the curriculum's lowest step, 0.762 m, it clears the first hurdle on 4 of 8 starts and then falls before the second.",
              "The run-up is the limit: about 4 m/s at the first hurdle where a high-school hurdler arrives near 7. The start from blocks reaches 5.0 m/s at 13.7 m, on the 95th-percentile body."],
             None, "Rebuild the approach on the blocks start and, later, the v4 sprinter; then work the trail leg.",
             body="v3 body with 3D hips (hip abduction and rotation freed)."),
    ]

    ball_cards = [
        card("bat", "Baseball swing", [chip("run"), chip("study", "Ceiling study shown")],
             [vid("bat_v6_knots.mp4", out("bat_v6_knots.mp4"), "Swing with contraction knots and reflexes on",
                  "In robolab's representation (contraction knots, reflexes on): 21.6 m/s on pitches it never trained on."),
              vid("bat_v6.mp4", out("bat_v6.mp4"), "Open-loop ceiling swing",
                  "Ceiling study: an open-loop excitation program with the reflexes off, 25.2 m/s.")],
             ["The earlier hitch-free swing was slow because of its plan. The arms and wrists fired at full power only 2 to 8% of the swing, the bottom wrist cast early, and the bat peaked 42 ms before contact. The fast swing turns the pelvis at full drive into its yaw limit, keeps the spine coiled, fires short arm bursts with no co-contraction, and whips the bottom wrist through 0.8 rad in the last 60 ms. That wrist runs at 1,069 °/s in the open-loop program and 930 °/s in the reflex-on swing; college hitters manage 1,093 ± 354 (lower hand).",
              "The open-loop program scores 25.2 m/s on 24 fresh pitches and hits all 24. It was built from 6 of the 18 grid pitches (their locations at 76 mph), so the 24 fresh pitches are the held-out test. Distilled into contraction knots with the reflexes on, it keeps 82 to 85% of that speed: 21.6 m/s, with 2 to 4 of 24 pitches missed by 1 to 3 cm. That swing is not a champion of any trial, because the open-loop program holds them. The trunk turns at 51 to 60% of MLB rates and elbow extension at 38 to 39%. Landing the step 62 ms later cut the pause before the swing from 115 ms to 50 ms."],
             table(["Swing", "18 test pitches", "24 new pitches"],
                   [["Hitch-free (before)", "#13.78", "#13.86"],
                    ["Codex pure search", "#14.72", "#14.79"],
                    ["Reflexes on, knots", "#23.1–24.5", "#20.6–21.6"],
                    ["Open-loop program (ceiling study)", "#25.17", "#25.24"]]),
             "Train the knots directly on fresh continuous pitches, and shorten the pre-swing pause.",
             body="Athlete body: strength ×1.5, every muscle's peak speed 3.0 L0/s, a pivot root with a yaw hinge and a slide, no whole-body balance. On the human-calibrated body at strength 1.0 the champion is 10.3 m/s."),
        card("dribble", "Dribbling", [chip("run")],
             [vid("dribble_btl.mp4", out("dribble_btl.mp4"), "Three passes through the legs in a row",
                  "Through the legs: three passes in a row on a start found by scanning seeds, with a slow-motion replay of the pass."),
              vid("codex_crossover.mp4", CODEX + "competitor_20260927__video_dribble_crossover_25_tcn.mp4", "Crossover dribble, Codex champion",
                  "Crossovers: Codex's champion, 7.52 per 15 s run. The ball is eventually lost on every run.")],
             [f"**Through the legs.** A stance planner picked a staggered lunge with the trunk twisted toward the lead leg, and catch spots that both hands can reach from behind the ball. On the 25 arena starts the mean longest streak is {V('dribble_btl_streak_25', 2)} passes in 15 s and never more than {streak_max}; {btl_any} of {btl_n} starts get at least one good pass and {btl_two} get two in a row. The agent's own 8 s check on 24 fresh starts (not saved as a trial) had the first pass complete on 22 (92%), the return on 10 (42%), and 33 of 61 passes good, with a streak of 3 on only 1 or 2 of 32 fresh starts. The earlier \"between the legs\" video was a low crossover in front of the lead foot: the ball never went through the gap, and the leg-gate count for it is 0 on all 25 starts.",
              "**Crossovers.** Codex's small learned correction from the recent ball motion doubled the count to 7.52 per 15 s run. The trunk still pumps and the hands are rigid paddles."],
             table(["Trial", "Champion", "Was"],
                   [["Through the legs, 25 starts (good passes ÷ max(attempts, 10))", f"#{V('dribble_btl_25', 3)}", "#0.000"],
                    ["Through the legs, longest streak (mean of 25)", f"#{V('dribble_btl_streak_25', 2)}", "#–"],
                    ["Crossovers per 15 s run, 25 starts", f"#{V('dribble_crossover_25')}", "#3.72"]]),
             "The return pass: the arms can stop a fast, flat ball but cannot follow it down and drive it back up, and they lag the plan. Try catching it while it is still rising, catch spots about 25 cm closer, and a trunk turn into the catch.",
             body="Stationary pivot bodies. Through the legs: v3 with fingers. Crossovers: v1 with rigid paddle hands."),
        card("tt", "Table tennis", [chip("stuck")],
             [vid("myo_tt_r5.mp4", out("myo_tt_r5.mp4"), "Five solved serves in a row",
                  "Five solved serves in a row (seeds 98045 to 98049) by the phase-2 champion. It solves 33% of serves, so this is a chosen streak, not a rally."),
              vid("myo_tt_strokes.mp4", out("myo_tt_strokes.mp4"), "Chop, wrist flick and low scoop",
                  "Chop, backhand flick and low forehand scoop with real ball spin, at the best angles found.")],
             ["Predicts the ball through the bounce, slides the pelvis onto its path, latches the ready posture on time-to-paddle and sets the paddle face from an aim law. Phase 1 is 100%. Phase 2 is **33%** over 300 serves, and the winner scored 64%.",
              "The aim is accurate. The arm does not carry it out: a forehand asked to turn its forearm 1.20 rad reaches 0.44, and the face follows 0.53 to 0.66 of an aimed change on the forehand and 0.13 to 0.28 on the backhand (1 would be perfect). Live moment arms fix the arm's tracking (backhand error 0.80 to 0.21 rad, forehand yaw follow 0.66 to 1.01), but the tracked arm plays like a new player and needs a long practice run. Where the ball meets the paddle decides most forehands: 67% solved within 3 cm of the centre, 1 in 7 on the rim.",
              "Your strokes: the chop goes high because the aim rule opens the forehand face about 40° and the forehand path cannot get steeper than about 40° down. The best chop is the backhand, commanded at a 60° face and a 40° downward path, which reaches −4° and 33° down (4 cm over the net, 11 rev/s of backspin, 3 of 11 landed). The wrist flick makes topspin, under 5 rev/s, because its paddle reaches only 1.3 to 1.5 m/s."],
             None,
             "Running now (agent T, started 29 Sep after your go-ahead): a long practice run of the live-tracked arm on both sides, and an inverse posture map from the live moment arms. 90% is 10 points above the best reported result (80.3%, a preprint) and 26 above the challenge winner.",
             body="The official MyoSuite table-tennis body: 273 muscles and 2 pelvis actuators."),
    ]

    soccer_cards = [
        card("balance", "One-leg balance", [chip("run")],
             [vid("soccer_balance_300.mp4", out("soccer_balance_300.mp4"), "Standing on one leg for the first 40 seconds of a 298 second hold",
                  "The first 40 s of a 298 s one-leg stance on the 290-muscle body.")],
             ["The hold is steered by the sensed centre of pressure, with a slow centring loop and per-posture muscle moment arms. The centring loop is what carries a hold past 96 s. On a 310 s trial, **12 of 20** fresh stances stay on one leg for at least 300 s, and a version with a tuned lift holds 15 of 20 (p 0.23 on 20 starts, not promoted). The short two-leg trial (3 s on each leg, at most 6) went from 1.96 to 3.08 s, with the right leg still the weak one (0.63 s).",
              "Round 4 overturned the first diagnosis: in single support the standing foot's heading stays within 0.02 rad, so it does not spin. What was wrong was the controller's hip model, measured at the start posture: the gluteal muscles' moment arms change sign where one-leg stance happens (one muscle's rotation torque per unit activation runs from −29 to +37 N·m). On the 20 starts every failure was at the lift: the swing foot leaves the ground still carrying 20 to 40% of body weight, which throws the capture point 5 to 6 cm outward, past the ±2 cm the sole can absorb, and the standing foot then spins 0.3 to 0.4 rad. On 40 new starts the lift challenger holds 20 s on 35 and loses 5: one in the lift, one in the set, three in the hold after the lift, where the pelvis yaw sits at the stance hip's stop, goes into a 0.75 s limit cycle and the frontal plane then runs away."],
             None,
             "The 40-start trial `soccer_single_leg_310_40` (its seeding run is in progress) will separate 12 of 20 from 15 of 20. The log points at the hip strategy: throwing the trunk into the fall helps the fast transient but feeds a slow outward drift.",
             body="The official MyoSuite soccer body, 290 muscles."),
        card("soccer", "Penalty kick", [chip("done", "Phase 1 champion"), chip("stuck", "Phase 2 blocked")],
             [vid("myo_soccer.mp4", out("myo_soccer.mp4"), "Penalty kick, phase 1", "Phase 1: 100% of 50 starts."),
              vid("soccer_p2_v4.mp4", out("soccer_p2_v4.mp4"), "Phase 2 attempt", "Phase 2 attempt: one step, then a fall.")],
             ["Shift weight, step, plant beside the ball, swing with a hip-flexor burst and knee snap latched on ball contact, aiming away from the keeper. Phase 1 scores every time. Phase 2 starts 0.02 to 1.4 m from that stance and lasts 10 s, and it scores 0 of 100 (the 2025 winner scored 32%).",
              "Two measured walls. The phase-1 kick is a trajectory from one exact start, and from a settled stance it scores 0 of 30 starts even within 0.3 m of the phase-1 stance. And this body cannot walk upright: the abdominal muscle's passive pull plus the upper body's weight need 84 to 123% of the back extensors' capacity whenever the chest is upright, so the chase-tag walker folds its spine within 0.5 s."],
             None,
             "Rebuild the kick in stages from the settled stance, then a faster approach.",
             body="The official MyoSuite soccer body, 290 muscles."),
    ]

    myo_cards = [
        small("Relocate", [chip("scored")], vid("relocate_v6.mp4", out("relocate_v6.mp4"), "Relocate, round 6",
                                               "A 295 g object from the far left, carried and held inside the box."),
              f"Official score {V('relocate_p2eval_official', 3)} on the evaluation environment (was 0.210), genuine lifts {V('relocate_p2eval_lift', 3)}. On the easier phase-2 environment, lifts {V('relocate_p2_300', 3)}. MyoSuite 2.12.2 steps a second copy of the scene whose receptacle sits at the random target, invisible to the observation, while the visible box has no walls. Scores here are not comparable to the 2023 winner's 0.343."),
        small("Chase tag", [chip("scored")], vid("myo_chase_v2.mp4", out("myo_chase_v2.mp4"), "Chase tag", "Two leg tracks with turning."),
              f"Phase 1 {V('chase_p1', 3)}; phase 2 {V('chase_p2', 2)} against the 2023 winner's 0.666 on the final evaluation. Each leg loops stance, push, lift and reach on its own sensed events; a step-turn loop turns toward an opponent behind."),
        small("Walking on the myoLeg", [chip("scored")], vid("myo_walk_v2.mp4", out("myo_walk_v2.mp4"), "MyoLeg walking with the longer stride", "The 80-muscle leg model with the step-length champion: 0.46 m steps at 1.44 m/s, until it reaches the arena edge."),
              f"Step length {V('walk_stride', 2)} m (was 0.36, people about 0.7), at about 1.45 m/s at any commanded speed: the longer-stride gait trades pace control for step length. Quiet standing survives 2 to 4 of 4 pushes of 60 to 80 N, not 100 N; while walking, pushes of 50 N and more knock it over."),
        small("Baoding balls", [chip("scored")], vid("myo_baoding_v3.mp4", out("myo_baoding_v3.mp4"), "Baoding balls", "Palm tilt and roll tied to the ball angle."),
              f"Score {V('baoding_p2', 3)} against the 2022 winner's 0.55. It holds both balls and nudges them but never found a rolling gait."),
        small("Die reorientation", [chip("stuck")], vid("myo_die_v3.mp4", out("myo_die_v3.mp4"), "Die", "Finger flips plus palm tilt and roll."),
              f"No full solves (0 of 100) against the co-winners' 0.13. It removes {V('die_p2_progress', 2)} rad of the die's rotation (was 0.19)."),
        small("Bimanual handover", [chip("stuck")], vid("bimanual_v4.mp4", out("bimanual_v4.mp4"), "Bimanual handover", "The arm holds the box out steadily."),
              f"Staged progress {V('bimanual_stages', 2)} (was 0.33) with no full success. The prosthesis mostly presses its hand against the held box; it is not yet a grip."),
    ]

    # ------------------------------------------------------------ bodies -------------
    bodies = table(
        ["Body", "What it is", "Sprint ceiling, torso free", "Used for"],
        [
            ["Average (v2, v3)", "Average adult. v3 adds elastic Achilles and quadriceps tendons.", "6.89 m/s on v3", "Running, standing jump, dribble, hurdles, most older results"],
            ["95th percentile", "Strength ×1.32, muscle speed ×1.2 and tendon stiffness ×1.5 (each a 95th percentile of published data), activation time constants ×0.87 (inferred; no population distribution exists).", "9.69 m/s on v3", "Sprint, blocks, long jump"],
            ["Elite, old profile", "Strengths set per muscle from memory of the papers (hip extensors ×1.6, vasti ×1.3, speed ×1.3). A check on 28 Sep found iliopsoas, vasti, soleus, gastrocnemius, the quadriceps tendon and activation set too strong.", "unverified", "Results marked provisional"],
            ["Elite, literature (elite2)", "Every part cited. Elite knee and ankle extensors sit near the untrained mean.", "8.5 on v3, 9.28 on v4", "New trials"],
            ["v4, calibrated", "v3 with two literature-backed changes: quadriceps series stiffness 250 to 1000 N/mm, hip speeds 15 to 18.5 (extension) and 29 (flexion) rad/s.", "8.2 average, 10.45 95th pct., 9.28 elite2", "Sprinters being tuned now"],
            ["Athlete (bat)", "The batter's body: strength ×1.5, every muscle's peak speed 3.0 L0/s, damping 1.5, on a pivot root with a yaw hinge and a slide. No whole-body balance.", "–", "Baseball swing"],
            ["Official MyoSuite bodies", "80 to 290 muscles on wrapped tendons, with the official environments and scoring.", "–", "Table tennis, soccer, chase tag, relocate, baoding, die, bimanual, walking"],
        ], wide=True)

    # ------------------------------------------------------------ codex --------------
    codex = table(
        ["Result", "Codex reports", "In this arena"],
        [
            ["Standing jump, legal distance (8 starts)", "1.363 m (temporal recovery)", "Run here 27 Sep: promoted"],
            ["Crossovers, 25 starts", "7.52, later 9.08 (R9)", "7.52 run here 27 Sep: promoted. 9.08 (R9): running now, approved 29 Sep"],
            ["Standing jump, robustness (32 starts)", "1.3397 m, 32 of 32 legal at 3 s; 57 of 64 legal at 8 s on fresh starts (R7)", "Ours 1.3153, 64 of 64 at 3 s and 0 of 64 at 8 s on the same fresh starts. R7 running now, approved 29 Sep"],
            ["Bat power", "14.72 m/s, pause before and after contact kept", "Run here 27 Sep: promoted, later beaten by the open-loop program"],
            ["Dribble rounds 10 and 11", "R10 no promotion. R11 (fingered hand) is running", "–"],
        ], wide=True)

    # ------------------------------------------------------------ running now --------
    working = table(
        ["Workstream", "Where it stands", "Next"],
        [
            ["Sprint on the v4 body (agent S)", f"The average-body runner is in the arena at {V('sprint_top_speed_v4')} m/s. The agent's log has newer candidates on the 95th-percentile v4 body (about 7 m/s) and the average body that are not entered yet.", "Enter them, then the elite body"],
            ["Long jump (agent L)", "A landing search on a program not yet entered: 3 of 32 captured take-offs roll over and 2 foul. Diagnosed at 01:30 as a timing problem of a fixed-time landing program; a ballistic-time clock scan gives 0 roll-overs on the 30 legal take-offs, with marks of 4.6 to 4.98 m.", "Enter it on the 16-start trial; a v4 family after a v4 sprinter"],
            ["Balance and soccer (agent O)", "New 40-start trial `soccer_single_leg_310_40` is seeding. The lift challenger holds 20 s on 35 of 40; five fail (details under One-leg balance).", "Ablations of the hip strategy on the failing seeds"],
            ["Table tennis above 90% (agent T)", "Started 29 Sep after your go-ahead.", "Long practice of the tracked arm; inverse posture map"],
            ["Codex R7 and R9 in this arena", "Running now: the jump robustness policy (1.3397 m) and the crossover policy (9.08).", "Verdicts here, then this page"],
            ["Compiler fixes", "Being ported onto today's main in an isolated worktree, with the stage-identity check and the spec suite, then merged.", "Land on main"],
            ["Landing robolab on main", "Follows the cross-evaluations. Includes a build-and-run check.", "Land on main"],
            ["MyoSuite relocate bug report", "Drafting with a minimal reproduction.", "File upstream"],
            ["Dribble through the legs, bat speed, runner, hurdles, relocate", "Written up in the handoff for Codex to pick up (bits/tungsten-robolab/HANDOFF_20260929.md)", "Codex chooses"],
        ], wide=True)

    # ------------------------------------------------------------ requests -----------
    requests = table(
        ["You asked", "Where it stands"],
        [
            ["A natural runner: power leg extended, other knee and arm up", "Built and improved: 7.3° from human running (was 9.1°) on the 12-start trial."],
            ["Batter hitch, before and after contact", "After contact: fixed for the 13.9 m/s v5 swing (the stall was the wrist and the pelvis hitting their joint limits). The 21.6 m/s knots swing has a pause before the swing again (50 ms; it fails the guard-clean trial on 2 of 24 pitches)."],
            ["Dribble: a visible crossover, less back, more elbow, fingers", "Crossover 7.52 per 15 s run. The trunk still pumps. The fingered hand is built (opt-in); no evidence of a gain yet, and Codex's fingered-hand search is running."],
            ["A better long-jump run and take-off", "4.9 m on one start; the sprinter is the run-up."],
            ["Hurdles at high-school height", "At 0.991 m: the lead leg clears and the trail leg catches at the first hurdle. At 0.762 m: hurdle 1 cleared on 4 of 8 starts. Waiting on run-up speed."],
            ["Table tennis backhand, wrist flick, chop, low scoop", "The backhand exists (23% of backhand serves solved). Chop, flick and scoop were measured with real ball spin: the best chop lands 3 of 11, the flick 0 of 20, the scoop 2 of 20."],
            ["Soccer kick with the inside of the foot", "Not yet: the best attempt strikes with the toes."],
            ["MyoLeg longer strides", f"{V('walk_stride', 2)} m (was 0.36; people about 0.7), at about 1.45 m/s."],
            ["Toe-touch and toe-off keyframes only, alternating legs", "As a whole controller it falls. As corrections mid-stance follows; the leg pair moves as negatives of each other (gain about 1.0), the arms do not."],
            ["One toe-off keyframe too many", "Drop the one at 30% of the stride, keep toe-off: the keyframe-chunk runner falls on 1 of 48 starts instead of 6."],
            ["A 95th-percentile body", "Done, and a v4 body calibrated to human data."],
            ["Running motion-capture data", "Fukuchi 2017 treadmill running, in the trial run_natural_mocap."],
            ["Bolt's mechanics from blocks", "Keyframes built and used. The runner takes 6.72 s to 30 m against Bolt's 3.78 s."],
            ["A drag-the-joints keyframe editor", 'Done: <a href="https://claude.ai/artifact/HvFRzvSmo8esj7A2ELnxng">Keyframe Bench</a>.'],
            ["Demos on yaks.app", "thecompanygardener.yaks.app/robolab, last refreshed 27 Sep. The videos above are newer."],
        ], wide=True)
    requests = requests.replace("&lt;a href=&quot;https://claude.ai/artifact/HvFRzvSmo8esj7A2ELnxng&quot;&gt;Keyframe Bench&lt;/a&gt;",
                                '<a href="https://claude.ai/artifact/HvFRzvSmo8esj7A2ELnxng">Keyframe Bench</a>')

