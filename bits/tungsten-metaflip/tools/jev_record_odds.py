#!/usr/bin/env python3
"""Ask TypeSafe's Jev (the `jev` CLI, via OpenRouter) how likely each live
Metaflip shape holds a GF(2) matrix-multiplication rank world record.

  tools/jev_record_odds.py                 # query every live shape, print a table
  tools/jev_record_odds.py --dry-run 9x9x9 # print the state text sent for a shape
  tools/jev_record_odds.py --out DIR       # keep request/response JSON per shape
  tools/jev_record_odds.py --with-schemes  # also show Jev the full live scheme

Live ranks come from $METAFLIP_HOME/checkpoints/gf2/<shape>/best.txt (default
~/.tungsten/metaflip). The public comparison is a curated, dated table below:
update PUBLIC_AS_OF and the notes when the literature moves. Jev answers two
questions per shape: `holds` (nothing lower is known anywhere, i.e. Metaflip
holds or co-holds the record), `new` (strictly below every prior GF(2)-valid
publication, i.e. a new record credited to Metaflip) and `optimal` (the rank
is the true minimum, so no further improvement is possible). The state carries
the best proven lower bound (see LOWER). These are model judgments over the
stated facts, not a prior-art audit.
"""
import argparse, concurrent.futures, json, os, pathlib, subprocess, sys

PUBLIC_AS_OF = "2026-09-22"

CONTEXT = (
    "Question domain: upper bounds on the bilinear (non-commutative) rank of {s} "
    "matrix multiplication with coefficients in GF(2). Integer-coefficient schemes "
    "reduce mod 2 and count as GF(2)-valid; schemes that need 1/2, 1/4, 1/8 or "
    "complex coefficients do not. As of {asof} the main public records are "
    "Sedoglavic's FMM catalogue (fmm.univ-lille.fr), Perminov's FastMatrixMultiplication "
    "repository (best ranks over ternary ZT, Z and Q), matmulcatalog (which records the "
    "fields each scheme is valid over, including F2), AlphaTensor (2022, includes mod-2 "
    "searches), AlphaEvolve (2025), and flip-graph papers by Kauers, Moosbauer, Poole, "
    "Wood, Arai and others, several of which search GF(2) directly.\n\n"
    "Project: Metaflip, an open-source GF(2) flip-graph search and block-composition "
    "fleet. Its current exact scheme for {s} has rank {ours}, re-verified today by "
    "expanding the complete matrix multiplication tensor over GF(2).\n\n"
    "Public comparison for {s}: {note}\n"
    "Best GF(2)-valid rank the project knows of from anyone else: {pub}. {cmp}\n\n"
    "Provenance of Metaflip's scheme: {how}\n\n"
    "Lower bound: {lower}"
)

TIE_HOW = ("Metaflip has searched this shape repeatedly during 2026 with CPU and GPU "
           "flip-graph walkers and has not gone below the public rank.")
HK = ("Hopcroft and Kerr (1971) established ceil(7n/2) as optimal for noncommutative "
      "2x2 by 2xn multiplication, so this rank is believed optimal.")

# shape: (best GF(2)-valid rank by others, public note, provenance of ours or None)
PUBLIC = {
    "2x2x2": (7, "Strassen (1969). Winograd and Hopcroft-Kerr (1971) proved 7 is optimal "
              "for 2x2 matrices, over GF(2) as well.", None),
    "2x2x5": (18, "Every catalogue lists 18. " + HK, None),
    "2x2x6": (21, "Every catalogue lists 21. " + HK, None),
    "2x2x7": (25, "Every catalogue lists 25. " + HK, None),
    "2x2x8": (28, "Every catalogue lists 28. " + HK, None),
    "2x2x9": (32, "Every catalogue lists 32. " + HK, None),
    "2x3x4": (20, "Perminov lists 20 over ZT, Z and Q.", None),
    "2x3x5": (25, "Perminov lists 25 over ZT, Z and Q; AlphaTensor (2022) also has 25.", None),
    "2x4x5": (33, "Perminov lists 33 over ZT and Z. A rank-32 scheme is listed only over "
              "Q/complex coefficients (AlphaEvolve era) and is not known to be GF(2)-valid.", None),
    "2x5x6": (47, "Perminov lists 47 over ZT, Z and Q; AlphaEvolve (2025) also reports 47.", None),
    "3x3x3": (23, "Laderman (1976). No rank-22 scheme is known over any field despite "
              "extensive SAT, flip-graph and AlphaTensor searches; the best lower bound is "
              "19 (Blaser 2003).", None),
    "3x3x4": (29, "Perminov lists 29 over ZT, Z and Q.", None),
    "3x3x5": (36, "Perminov lists 36 over ZT, Z and Q; AlphaTensor (2022) also has 36.", None),
    "3x4x4": (38, "Perminov lists 38 over ZT, Z and Q.", None),
    "3x4x5": (47, "Perminov lists 47 over ZT, Z and Q; AlphaTensor (2022) found 47.", None),
    "3x4x6": (54, "Perminov lists 54 over ZT, Z and Q (Z/Q known before his ternary version).", None),
    "3x4x7": (64, "Perminov lists 64 over ZT and Z. A rank-63 scheme is listed only over "
              "Q/complex coefficients and is not known to be GF(2)-valid.", None),
    "3x5x5": (58, "Perminov lists 58 over ZT, Z and Q; AlphaTensor (2022) also has 58.", None),
    "3x5x6": (68, "Perminov lists 68 over ZT, Z and Q; AlphaEvolve (2025) also reports 68.", None),
    "3x5x7": (79, "Perminov lists 79 over ZT, Z and Q (previous best 80 from AlphaEvolve 2025).", None),
    "4x4x4": (47, "AlphaTensor (Fawzi et al. 2022) found 47 over GF(2). Integer schemes need "
              "49; the rank-48 scheme (AlphaEvolve 2025 and rational follow-ups) needs 1/2 or "
              "complex coefficients, so it is not GF(2)-valid.", None),
    "4x4x5": (60, "matmulcatalog lists a GF(2)-specific rank-60 scheme; Perminov lists 61 "
              "over ZT, Z and Q.", None),
    "4x4x6": (73, "Perminov lists 73 over ZT, Z and Q.", None),
    "4x5x5": (76, "Perminov lists 76 over ZT, Z and Q; AlphaTensor (2022) found 76.", None),
    "4x5x6": (90, "Perminov lists 90 over ZT, Z and Q.", None),
    "4x5x7": (104, "Perminov lists 104 over ZT, Z and Q.", None),
    "4x5x8": (118, "Perminov lists 118 over ZT, Z and Q (previous best 122).", None),
    "4x6x6": (105, "Perminov lists 105 over ZT, Z and Q.", None),
    "4x6x7": (123, "Perminov lists 123 over ZT, Z and Q.", None),
    "4x6x8": (140, "Perminov lists 140 over ZT, Z and Q.", None),
    "5x5x5": (93, "Moosbauer and Poole (2025), flip graphs with symmetry; Perminov lists 93 "
              "over ZT, Z and Q.", None),
    "5x6x7": (150, "Perminov lists 150 over ZT, Z and Q.", None),
    "6x6x6": (153, "Moosbauer and Poole (2025); Perminov lists 153 over ZT, Z and Q.", None),
    "7x7x7": (248, "The best previously published GF(2)-valid scheme has rank 248 (a Sedoglavic "
              "2017 construction). Perminov lists 250 over ZT and Z and 249 over Q.",
              "found by mid-July 2026 through an exact outer-Strassen isotropy/placement "
              "composition, independently exhaustively gated; many distinct rank-247 "
              "presentations exist. The project labels it a candidate world record pending "
              "a complete prior-art audit; it has not been published or peer reviewed."),
    "8x8x8": (329, "329 = 7 x 47, the Kronecker product of Strassen's 2x2 and AlphaTensor's GF(2) "
              "4x4 schemes; matmulcatalog lists it. Integer schemes give 343 and a rational "
              "scheme 336 (not GF(2)-valid).", None),
    "9x9x9": (486, "Perminov (2025-26) lists 486 over ZT, Z and Q (previous best 498); the "
              "Lille catalogue credits 486 to Perminov. The Kronecker square of Laderman's "
              "3x3 gives 529. No GF(2)-specific 9x9x9 scheme below 486 is known to the project.",
              "found on 2026-09-12 by a GF(2) flip-graph walk of about 81 billion moves "
              "seeded from Perminov's rank-486 ternary scheme (GF(2)-only reductions, like "
              "AlphaTensor's 4x4 rank 47 versus 49 over the integers). Not yet published; "
              "prior-art audit incomplete."),
    "10x10x10": (651, "Perminov lists 651 over ZT and Z (also 7 x 93, Strassen times the "
                 "5x5 record).", None),
    "11x11x11": (873, "Perminov lists 873 over ZT and Z.", None),
    "12x12x12": (1068, "Perminov lists 1068 over ZT and Z. A rank-1040 scheme exists, but "
                 "matmulcatalog lists it over F3/Q/R/C only, excluding GF(2).", None),
    "13x13x13": (1426, "Perminov lists 1426 over ZT and Z. Rational schemes of rank 1420 "
                 "(LITA) and 1421 use denominators 2, 4 and 8, so they do not reduce to GF(2).",
                 "an exact GF(2) block composition built from GF(2)-only small records such "
                 "as AlphaTensor's rank-47 4x4 scheme, found in the project's 2026 history. "
                 "No other GF(2)-specific 13x13x13 composition is known to the project, but "
                 "comparable compositions are straightforward for experts. Not yet published."),
    "14x14x14": (1725, "Perminov lists 1725 over ZT and Z. A rational rank-1603 LITA scheme "
                 "uses even denominators (1/2, 1/4, ...), and matmulcatalog's rank-1719 "
                 "entry explicitly excludes F2; neither is GF(2)-valid.", None),
    "15x15x15": (2058, "Perminov lists 2058 over ZT, Z and Q. The Kronecker product of the "
                 "3x3 and 5x5 records gives 23 x 93 = 2139.",
                 "Metaflip GF(2) search in September 2026 improved an exact rank-2008 GF(2) "
                 "block composition (built on GF(2)-only small records) to 2006. Not yet "
                 "published; prior-art audit incomplete."),
    "16x16x16": (2401, "The catalogues list 2401 over ZT and Z (49 x 49) and a rational LITA "
                 "scheme of rank 2247 that uses even denominators (not GF(2)-valid). Rank "
                 "2209 = 47 x 47 is the Kronecker square of AlphaTensor's GF(2) 4x4 scheme, "
                 "implied by the 2022 result but not listed explicitly in the catalogues the "
                 "project checked.",
                 "the Kronecker square of AlphaTensor's GF(2) rank-47 4x4 scheme (47 x 47); "
                 "Metaflip's search has not gone below it."),
}

# Proven rank lower bounds for small formats (rank is invariant under permuting
# n, m, p). Every other shape takes the best of: these, carried up by
# restriction (a format contains every smaller one); Blaser's ceil(5/2 n^2 - 3n)
# for n x n over any field; and the trivial flattening bound max(nm, mp, np).
LOWER = {
    (2, 2, 2): (7, "Winograd and Hopcroft-Kerr (1971) proved 7 optimal; a 2026 computer proof "
                   "over GF(2) (arXiv 2603.07280) re-confirms it"),
    **{(2, 2, k): (-(-7 * k // 2), "7n/2 is a proven lower bound for 2x2 by 2xn, exact over GF(2) "
                   "(Hopcroft-Kerr 1971; also proved over arbitrary fields), matching ceil(7n/2)")
       for k in range(5, 10)},
    (2, 3, 4): (20, "R(<3,2,m>) >= ceil(24m/5) over arbitrary fields (arXiv 2609.14393, September "
                    "2026) gives 20, matching Hopcroft-Kerr's upper bound, so 20 is proven optimal"),
    (2, 3, 5): (24, "R(<3,2,m>) >= ceil(24m/5) over arbitrary fields (arXiv 2609.14393, September 2026)"),
    (2, 4, 5): (30, "R(<n,2,m>) >= (n+2)m for n >= 4 over arbitrary fields (arXiv 2609.14393, "
                    "September 2026), with n=4, m=5"),
    (2, 5, 6): (42, "R(<n,2,m>) >= (n+2)m for n >= 4 over arbitrary fields (arXiv 2609.14393, "
                    "September 2026), with n=5, m=6"),
    (3, 3, 3): (20, "raised from 19 (Blaser 2003) to 20 over GF(2) by a 2026 computer-assisted proof "
                    "(arXiv 2603.07280); rank 23 has stood since Laderman 1976 and extensive SAT and "
                    "flip-graph searches have found no rank-22 scheme"),
    (3, 3, 4): (25, "proved over GF(2) by a 2026 computer-assisted proof (arXiv 2603.07280)"),
    (3, 4, 4): (29, "proved over GF(2) by a 2026 computer-assisted proof (arXiv 2603.07280)"),
}


def lower_bound(shape, ours):
    n, m, p = sorted(shape_key(shape))
    if (n, m, p) in LOWER:
        bound, why = LOWER[(n, m, p)]
    else:
        bound, why = max(n*m, m*p, n*p), "the trivial flattening bound max(nm, mp, np)"
        if n == m == p and -(-(5*n*n - 6*n) // 2) > bound:
            bound, why = -(-(5*n*n - 6*n) // 2), "Blaser's 5/2 n^2 - 3n bound over arbitrary fields (1999)"
        for small, (b, _) in LOWER.items():
            if all(x <= y for x, y in zip(small, (n, m, p))) and b > bound:
                bound = b
                why = (f"restriction from {'x'.join(map(str, small))}, whose rank over GF(2) is at "
                       f"least {b} (a larger format contains every smaller one)")
        why += "; no shape-specific lower bound closer to the best known rank is known to the project"
    if bound == ours:
        return f"{bound}, {why}. This equals Metaflip's rank, so the rank is proven optimal."
    return (f"{bound}, {why}. The gap between this lower bound and Metaflip's rank {ours} is "
            f"{ours - bound}; optimality is not proven.")


QUESTIONS = {
    "holds": ("As of September 2026, is rank {ours} the lowest GF(2)-valid rank known anywhere "
              "for {s} matrix multiplication, so that Metaflip holds or co-holds the world record?"),
    "new": ("Is rank {ours} strictly lower than every GF(2)-valid scheme previously published "
            "for {s}, so that Metaflip can claim a new world record for this shape?"),
    "optimal": ("Is rank {ours} the true minimum rank of {s} matrix multiplication over GF(2), "
                "so that no scheme with fewer products can exist and no further improvement "
                "is possible?"),
}


def shape_key(s):
    return [int(x) for x in s.split("x")]


def live_ranks(home):
    root = pathlib.Path(home) / "checkpoints" / "gf2"
    ranks = {}
    for best in root.glob("*/best.txt"):
        with best.open() as f:
            ranks[best.parent.name] = int(f.readline().split()[-1])
    return ranks


def scheme_text(home, shape):
    """The live scheme, one product per line: M5: A1,1+A2,2 * B1,1+B2,2 -> C1,1 C2,2"""
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    from jev_fill_decomposition import load_best
    n, m, p, U, V, W = load_best(pathlib.Path(home), shape)
    def entries(name, row, cols):
        return [f"{name}{b // cols + 1},{b % cols + 1}" for b in range(len(row)) if row[b]]
    lines = [f"M{t+1}: {'+'.join(entries('A', U[t], m))} * {'+'.join(entries('B', V[t], p))} -> "
             f"{' '.join(entries('C', W[t], p))}" for t in range(len(U))]
    return (f"\n\nMetaflip's complete rank-{len(U)} scheme for {shape} over GF(2) (each product "
            f"is (sum of A entries) * (sum of B entries), added into the listed C entries; "
            f"Ai,j is row i column j):\n" + "\n".join(lines))


def state_for(shape, ours, scheme=""):
    pub, note, how = PUBLIC[shape]
    if ours < pub:
        cmp = f"Metaflip's rank is {pub - ours} lower."
    elif ours == pub:
        cmp = "Metaflip's rank ties it."
    else:
        cmp = f"Metaflip's rank is {ours - pub} higher."
    text = CONTEXT.format(s=shape, ours=ours, asof=PUBLIC_AS_OF, note=note, pub=pub,
                          cmp=cmp, how=how or TIE_HOW,
                          lower=lower_bound(shape, ours)) + scheme
    questions = {k: {"type": "noul", "instructions": q.format(s=shape, ours=ours)}
                 for k, q in QUESTIONS.items()}
    return {"model": os.environ.get("JEV_MODEL", "jev-latest"), "state": text,
            "questions": questions}


def ask(shape, body, out_dir):
    req = out_dir / f"{shape}.request.json"
    req.write_text(json.dumps(body, indent=2))
    run = subprocess.run(["jev", "--raw", str(req)], capture_output=True, text=True, timeout=180)
    if run.returncode != 0:
        return shape, None, (run.stderr or run.stdout).strip()
    (out_dir / f"{shape}.response.json").write_text(run.stdout)
    return shape, json.loads(run.stdout), None


def probability(answer):
    """Pull P(yes) out of one Jev answer, whatever its exact envelope."""
    if isinstance(answer, (int, float)):
        return float(answer)
    if isinstance(answer, dict):
        for key in ("noul", "probability", "p", "yes", "p_yes", "score", "value"):
            if isinstance(answer.get(key), (int, float)):
                return float(answer[key])
        for value in answer.values():
            p = probability(value)
            if p is not None:
                return p
    return None


def answers(response):
    for key in ("answers", "results", "questions", "output"):
        if isinstance(response.get(key), dict):
            return response[key]
    return response


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("shapes", nargs="*", help="limit to these shapes (default: every live shape)")
    ap.add_argument("--home", default=os.environ.get("METAFLIP_HOME", str(pathlib.Path.home() / ".tungsten/metaflip")))
    ap.add_argument("--out", default=None, help="directory for request/response JSON")
    ap.add_argument("--dry-run", action="store_true", help="print the state text, send nothing")
    ap.add_argument("--with-schemes", action="store_true", help="append the full live scheme to each state")
    ap.add_argument("-j", "--jobs", type=int, default=8)
    args = ap.parse_args()

    ranks = live_ranks(args.home)
    shapes = sorted(args.shapes or ranks, key=shape_key)
    missing = [s for s in shapes if s not in ranks or s not in PUBLIC]
    if missing:
        sys.exit(f"no live checkpoint or public comparison for: {', '.join(missing)}")
    bodies = {s: state_for(s, ranks[s], scheme_text(args.home, s) if args.with_schemes else "")
              for s in shapes}
    if args.dry_run:
        for s in shapes:
            print(f"== {s}\n{bodies[s]['state']}\n")
            for k, q in bodies[s]["questions"].items():
                print(f"  {k}: {q['instructions']}")
            print()
        return

    out_dir = pathlib.Path(args.out or f"/tmp/jev-record-odds-{PUBLIC_AS_OF}")
    out_dir.mkdir(parents=True, exist_ok=True)
    results, errors = {}, {}
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        for shape, response, err in pool.map(lambda s: ask(s, bodies[s], out_dir), shapes):
            if err:
                errors[shape] = err
            else:
                results[shape] = response

    print(f"{'shape':>10} {'ours':>6} {'public':>6} {'lower':>6}  {'P(holds)':>8} {'P(new)':>7} {'P(optimal)':>10}")
    for s in shapes:
        pub = PUBLIC[s][0]
        if s in errors:
            print(f"{s:>10} {ranks[s]:>6} {pub:>6} {'':>6}  error: {errors[s][:80]}")
            continue
        a = answers(results[s])
        ph, pn, po = (probability(a.get(k)) for k in ("holds", "new", "optimal"))
        fmt = lambda p: f"{p:.2f}" if p is not None else "?"
        low = int(lower_bound(s, ranks[s]).split(",")[0])
        print(f"{s:>10} {ranks[s]:>6} {pub:>6} {low:>6}  {fmt(ph):>8} {fmt(pn):>7} {fmt(po):>10}")
    print(f"\nraw request/response JSON: {out_dir}", file=sys.stderr)
    if errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
