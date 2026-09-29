"""Build a linear-in-gap take-off program from two distilled ideals of starts with different penultimate gaps (L2).
  e(s; gap_err) = e_a(s) + gap_err x (e_b(s) - e_a(s)) / (gap_b - gap_a),  gap_err = (board - pen toe) - gap_a
so the skill's drive table e0 = e_a, its gap table e1 = (e_b - e_a) / (gap_b - gap_a), ik_gap0 = gap_a; the contraction / velocity /
acceleration knots are a's (the reflex gain is small). Both ideals should share the plant touchdown time (ROBOLAB_LJ_TD).
usage: interp_ik.py <ik_a.txt> <ik_b.txt> <gap_a> <gap_b> <out.txt> [nk=19] [post=0.24] [g=0.08]"""
import sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
from search import read_params


def main():
    fa, fb, ga, gb, out = sys.argv[1:6]
    ga, gb = float(ga), float(gb)
    nk = int(sys.argv[6]) if len(sys.argv) > 6 else 19
    post = float(sys.argv[7]) if len(sys.argv) > 7 else 0.24
    g = float(sys.argv[8]) if len(sys.argv) > 8 else 0.08
    A, B = read_params(fa), read_params(fb)
    td = A["ik_td"]
    lines = [f"# linear-in-gap program: e_a = {fa} (gap {ga}), e_b = {fb} (gap {gb})", "j_ik 1", f"ik_h {A['ik_h']!r}", f"ik_n {nk}", f"ik_td {td!r}",
             f"ik_gap0 {ga!r}", f"ik_end {td + post!r}", f"j_ik_g {g!r}", "j_ik_kdc 1.0", "ik_from 1"]
    roles = sorted({k.split("_", 2)[2] for k in A if k.startswith("ik_e0_")})
    for k in range(nk):
        for r in roles:
            for q in ("c", "v", "a", "e"):
                lines.append(f"ik_{q}{k}_{r} {A[f'ik_{q}{k}_{r}']!r}")
            ea, eb = A[f"ik_e{k}_{r}"], B.get(f"ik_e{k}_{r}", A[f"ik_e{k}_{r}"])
            lines.append(f"ik_g{k}_{r} {(eb - ea) / (gb - ga)!r}")
    open(out, "w").write("\n".join(lines) + "\n")
    print("wrote", out, len(lines), "lines; roles", len(roles), "td", td)


if __name__ == "__main__":
    main()
