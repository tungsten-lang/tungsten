"""rowstat (L7): failure accounting and take-off geometry of long_jump_eval json files. usage: rowstat.py file.json [file.json ...]"""
import json, sys
import numpy as np
for p in sys.argv[1:]:
    d = json.load(open(p)); rows = d["rows"]; n = len(rows)
    def legal(r): return (not r.get("error")) and (not r.get("foul")) and (not r.get("fell_approach")) and r.get("official_m", 0.0) > 0.0
    L = [r for r in rows if legal(r)]
    fell = sum(1 for r in rows if r.get("fell_approach"))
    fouls = sum(1 for r in rows if r.get("foul") and not r.get("fell_approach"))
    som = sum(1 for r in rows if r.get("somersault") and not r.get("foul") and not r.get("fell_approach"))
    other = n - len(L) - fell - fouls - som
    reach = sum(1 for r in rows if r.get("takeoff_toe_x") is not None)
    fx = np.array([r["foul_max_x"] for r in L]); off = np.array([r["board_offset_m"] for r in L])
    mk = np.array([r["official_m"] for r in L])
    print("%-34s n %d legal %d (%.1f%%) | fell %d fouls %d (%.1f%% of reach %d) somersault %d other %d | legal toe off %.3f +- %.3f foul_max_x %.3f +- %.3f | corr(mark, foul_max_x) %.2f | vx %.2f vz %.2f" % (
        p.split("/")[-1][:34], n, len(L), 100*len(L)/n, fell, fouls, 100*fouls/max(1, reach), reach, som, other, off.mean(), off.std(), fx.mean(), fx.std(),
        np.corrcoef(mk, fx)[0, 1], np.mean([r["takeoff_vx"] for r in L]), np.mean([r["takeoff_vz"] for r in L])))
