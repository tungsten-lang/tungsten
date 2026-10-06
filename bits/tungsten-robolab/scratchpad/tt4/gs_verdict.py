#!/usr/bin/env python3
"""Apply the PRE-REGISTERED pass rule of GRASP_SEARCH.md (with its amendment of 2 Oct) to gs_final.json, as written, for the champion grip and the best candidate.
Pass rule, on 70 validation serves (98030-98099) AND 100 serves of T3's set B (830000-830099): (1) lost before contact <= 5 % of the serves that reach contact,
(2) median pad error at contact <= 2 cm AND <= 3 deg, (3) >= 80 % of the serves reach contact; amendment: (4) the best candidate solves at least 10 points more serves than the
champion's grip on BOTH sets. Run from bits/tungsten-robolab after `grasp_search.py final`."""
import json

F = json.load(open("scratchpad/tt4/gs_final.json"))
for who in ("champion grip", "best candidate"):
    print(who)
    for sname, n in (("validation 98030-98099", 70), ("set B 830000-830099", 100)):
        m = F[f"{who} / {sname}"]
        c = max(m["contact"], 1)
        r1 = m["lost"] / c <= 0.05
        r2 = m["pos_med"] <= 2 and m["ori_med"] <= 3
        r3 = m["contact"] / n >= 0.80
        print(f"  {sname:24s} lost {m['lost']}/{m['contact']} ({'ok' if r1 else 'FAIL'})  pad error {m['pos_med']} cm, {m['ori_med']} deg ({'ok' if r2 else 'FAIL'})  contact {m['contact']}/{n} = {100 * m['contact'] / n:.0f} % ({'ok' if r3 else 'FAIL'})  solved {m['solved']}/{n}")
ok4 = True
for sname, n in (("validation 98030-98099", 70), ("set B 830000-830099", 100)):
    d = F[f"best candidate / {sname}"]["solved"] - F[f"champion grip / {sname}"]["solved"]
    pts = 100 * d / n
    print(f"amendment (4) {sname}: {'+' if d >= 0 else ''}{d} serves = {pts:+.0f} points ({'ok' if pts >= 10 else 'FAIL'})")
    ok4 &= pts >= 10
print("amendment (4) overall:", "PASS" if ok4 else "FAIL")
