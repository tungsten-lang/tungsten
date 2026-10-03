"""Write playground/calibrations/v5b.json from v5.json: the same rectus femoris / hip flexor split (rf 80, hip_flex_pos 170) but the vasti (knee_neg) UNCHANGED at v4's 230,
so the knee-extension capacity falls from 350 to 294 N m (the rectus femoris' smaller knee pull is NOT made up). Sibling of v5 found by the anat5 A/B: see scratchpad/anat5/LOG.md."""
import json, os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
d = json.load(open(os.path.join(ROOT, "playground", "calibrations", "v5.json")))
d["name"] = "v5b"
d["about"] = ("Opt-in sibling of v5 (select with ROBOLAB_BODY=v4 ROBOLAB_CALIB=v5b): the same source-based rectus femoris / hip flexor split as v5 (rf 80 N = 32 % of hip flexion, hip_flex_pos 170: hip flexion total 250 N m kept) but the vasti keep v4's value (knee_neg 230), "
              "so the knee-extension total is 294 N m (v4 and v5: 350) and the rectus femoris is 21.8 % of it (sources 15-22 %). Why it exists: in the anat5 A/B the champion's gears run on v5b with no retuning (gear 3 from gear-2 flying starts: 12/12 survive, steady 7.91 m/s, fold 110 deg, cadence 4.3/s; v4: 7.76 m/s, 96 deg, 4.16) "
              "while v5's stronger vasti (knee_neg 286: what makes up the knee total) makes the same stride fall (0/12): the controllers were tuned to the v4 vasti. The price is a 16 % weaker knee extension in total, which is the more conservative direction against v4.json's note that the model's capacities already exceed young men's voluntary maxima. A DIFFERENT BODY: not comparable with the v4 rows of the arena, nor with v5.")
p = d["params"]["peaks"]
p["value"] = {"hip_flex_pos": 170, "rf": 80}
p["v4"] = {"hip_flex_pos": 100, "rf": 150, "knee_neg": 230}
p["totals_kept"] = {"hip flexion": "hip_flex_pos + 1.0 x rf = 250 N m (v4: 100 + 150)",
                    "knee extension": "NOT kept: knee_neg 230 + 0.8 x rf 80 = 294 N m (v4: 230 + 120 = 350; v5 makes it up with knee_neg 286)",
                    "unchanged": "knee_neg (the vasti) 230, hip extension, knee flexion, ankle, toe, every speed / tendon / activation value"}
p["shares"] = {"v4": {"rf share of hip flexion": "60 % (150/250)", "rf share of knee extension": "34 % (120/350)"},
               "v5b": {"rf share of hip flexion": "32 % (80/250)", "rf share of knee extension": "21.8 % (64/294)"}}
p["evidence"] = p["evidence"][:3] + [
    "the vasti keep v4's 230 (unlike v5): the anat5 A/B found the champion's strides tuned to the v4 vasti (any stronger knee_neg makes gear 3 fall: rf 110 / 140 / 262: 2/12 survive, 95 / 155 / 274: 0/12, v5: 0/12, while rf 80 / hip_flex_pos 170 / knee_neg 230: 12/12), "
    "and a lower knee-extension total is the conservative direction against v4.json's note (capacities already 1.4-2.9x young men's voluntary maxima); the rectus femoris' knee share 21.8 % is inside the sources' 15-22 %"]
p["verified"] = "derived (as v5); the choice not to raise the vasti is an experimental finding, not a literature value"
d["kept"]["quadriceps tendon"] = ("the group's total series stiffness is unchanged; the v3 builder shares it among the group's muscles in proportion to their peak torques, so with the smaller rf the vasti's tendon is stiffer than in v4 (p95 XML: knee_neg 1996 -> 2376) "
                                  "and the rf's softer (1627 -> 1033): a consequence of the builder's sharing rule, not a separate choice")
d["split_check"]["v5b_shares"] = {"rf share of hip flexion %": 32.0, "rf share of knee extension %": 21.8, "knee extension total N m": 294}
tmp = os.path.join(ROOT, "playground", "calibrations", "v5b.json.tmp")
with open(tmp, "w") as f:
    json.dump(d, f, indent=1); f.write("\n")
os.replace(tmp, os.path.join(ROOT, "playground", "calibrations", "v5b.json"))
print("wrote v5b.json", p["value"])
