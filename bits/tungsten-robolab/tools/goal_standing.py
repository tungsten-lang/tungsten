#!/usr/bin/env python3
"""Goal standing from the arena, so that it is read from the champions and not typed by hand.

    python3 tools/goal_standing.py [--md FILE]          (from bits/tungsten-robolab; needs only the stdlib)

For every trial that stands for one of Erik's goals it prints the first champion recorded for that trial (date, value), the champion NOW
(date, value) and how many promotions lie between, then the arena's totals since 26 Sep 2026. A value is the champion's mean over the rollouts
that passed its guard (the board's convention: failed rollouts carry a -1e9 penalty), `n` the passes. Labels in the last column are part of
the number: LABELLED = the invented beyond-human body (never compare it with the human-body rows), ORACLE = open-loop muscle tables or an
ideal servo, TUNED = a program tuned to one start. The per-attempt record rate converts to the six-attempt competition as 1 - (1 - p)^6.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ARENA = os.path.join(os.path.dirname(HERE), "playground", "arena")

# (goal, trial, what the value is, label, optional transform)
GOALS = [
    ("increase the bat speed", "bat_power_fresh", "bat speed at contact, m/s, 24 fresh pitches", "human body (contraction knots + reflexes)"),
    ("", "bat_power_fresh_rep_p95", "bat speed, m/s, 24 fresh pitches", "LABELLED 95th-percentile body"),
    ("dribble through the legs", "dribble_btl_streak_25", "mean longest streak of good passes, 15 s, 25 starts", "ORACLE-class tables + servo"),
    ("", "dribble_btl_streak_fresh32", "mean longest streak, 32 fresh starts", "ORACLE-class tables + servo"),
    ("exceed 10 m/s in the sprint", "sprint_top_speed_v4_p95", "peak speed over 1 s, m/s, 95th-percentile human body", "human body"),
    ("", "sprint_top_speed_v4_beyond_fresh512", "peak speed, m/s, survivors of 512 fresh starts", "LABELLED beyond-human body"),
    ("long jump, then exceed human ability (record 8.95 m)", "long_jump_v4_p95", "official mark, m, one start", "human body, TUNED to one start"),
    ("", "long_jump_v4_p95_robust96", "mean official mark, m, 96 fresh starts", "human body"),
    ("", "long_jump_v4_beyond", "official mark, m, one start", "LABELLED, unlimited run-up, TUNED to one start"),
    ("", "long_jump_v4_beyond_robust96", "mean official mark, m, 96 fresh starts", "LABELLED, unlimited run-up (mean-mark program)"),
    ("", "long_jump_v4_beyond_record480", "P(legal jump > 8.95 m) per attempt, 480 fresh starts", "LABELLED, unlimited run-up (six-attempt program)"),
    ("exceed 90% for p2 in ping pong", "tt_p2_300", "serves returned legally, 300 serves", "official arm, muscle-driven"),
    ("balance five minutes on one leg", "soccer_single_leg_310_40", "fraction of 40 fresh stances that hold 300 s, official 310 s trial", "official task"),
    ("score all goals in the soccer trial", "soccer_p1", "goal rate, phase 1", "official task"),
    ("", "soccer_p2", "goal rate, phase 2 (random start, moving keeper)", "official task"),
]


def load_history():
    rows = []
    with open(os.path.join(ARENA, "history.jsonl")) as f:
        for line in f:
            try:
                rows.append(json.loads(line))
            except ValueError:
                pass
    return rows


def passed_mean(scores):
    ok = [x for x in scores if abs(x) < 1e8]
    return (sum(ok) / len(ok), len(ok)) if ok else (float("nan"), 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--md", help="also write the table to this file")
    args = ap.parse_args()
    champs = json.load(open(os.path.join(ARENA, "champions.json")))
    trials = json.load(open(os.path.join(ARENA, "trials.json")))
    hist = load_history()
    out = ["| goal | trial | what | first champion | champion now | promotions since | label |", "| --- | --- | --- | --- | --- | --- | --- |"]
    for goal, trial, what, label in GOALS:
        c = champs.get(trial)
        if not c:
            out.append(f"| {goal} | `{trial}` | {what} | | (none) | | {label} |")
            continue
        h = [r for r in hist if r["trial"] == trial and r.get("result") in ("seeded", "promoted")]
        first = h[0] if h else None
        now_mean, n = passed_mean(c.get("scores", [])) if c.get("scores") else (c["summary"]["mean"], c["summary"]["n"])
        fmean = first["summary"]["mean"] if first else float("nan")
        fs = f"{fmean:.3f}"
        if first and abs(fmean) >= 1e6:       # failed rollouts carry -1e9: the mean is then a count of failures
            nfirst = first["summary"]["n"]
            nfail = round(abs(fmean) * nfirst / 1e9)
            fs = "every rollout failed" if nfail >= nfirst else f"{nfail} of {nfirst} rollouts failed"
        now = f"{now_mean:.3f} (n {n})"
        if trial == "long_jump_v4_beyond_record480":
            now += f" = {100 * (1 - (1 - now_mean) ** 6):.0f}% of six-attempt competitions"
            if first and abs(fmean) < 1e6:
                fs += f" = {100 * (1 - (1 - fmean) ** 6):.0f}% of competitions"
        out.append(f"| {goal} | `{trial}` | {what} | {first['time'][:10] + ': ' if first else ''}{fs} | {c['time'][:10]}: {now} | {max(len(h) - 1, 0)} | {label} |")
    n_promoted = sum(1 for r in hist if r.get("result") == "promoted")
    n_seeded = sum(1 for r in hist if r.get("result") == "seeded")
    out.append("")
    out.append(f"Arena since {hist[0]['time'][:10]}: {len(trials)} trials, {n_seeded} champions seeded, {n_promoted} promotions, {len(hist)} recorded evaluations (last {hist[-1]['time'][:16]}).")
    text = "\n".join(out)
    print(text)
    if args.md:
        open(args.md, "w").write(text + "\n")


if __name__ == "__main__":
    sys.exit(main())
