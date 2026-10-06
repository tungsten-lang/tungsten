"""cmp6.py BASE.jsonl CAND.jsonl [CAND2.jsonl ...] [--tmax T]: PAIRED comparison of fr.py / fr6.py runs on the same seeds (labelled beyond-human body).

For each candidate against BASE: falls of each (counting only falls before --tmax seconds if given), the 2x2 table of fell / did not fall per seed
(recovered = BASE fell and CAND did not, new = the reverse), the exact two-sided McNemar (sign-test) p-value of the discordant pairs, falls by phase and by
time window (< 3 s early collapses, 3-9 s, 9-22 s, > 22 s), survivors' mean peak of each, and the mean paired peak difference over the seeds where neither fell.
Agent S6."""
import json
import math
import sys


def read(path):
    rows = {}
    for line in open(path):
        line = line.strip()
        if line:
            r = json.loads(line)
            if "error" not in r:
                rows[r["seed"]] = r
    return rows


def binom_two_sided(k, n):
    """exact two-sided sign test p for k of n discordant pairs going one way (p = 0.5)"""
    if n == 0:
        return 1.0
    m = min(k, n - k)
    p = sum(math.comb(n, i) for i in range(0, m + 1)) / 2 ** n
    return min(1.0, 2 * p)


def fell(r, tmax):
    return bool(r["fell"]) and (tmax is None or r["time"] <= tmax)


def windows(rows, tmax):
    w = {"<3s": 0, "3-9s": 0, "9-22s": 0, ">22s": 0}
    for r in rows.values():
        if fell(r, tmax):
            t = r["time"]
            w["<3s" if t < 3 else "3-9s" if t < 9 else "9-22s" if t < 22 else ">22s"] += 1
    return w


def phases(rows, tmax):
    p = {"START": 0, "HANDOVER": 0, "TOP": 0}
    for r in rows.values():
        if fell(r, tmax):
            p[r["phase"]] += 1
    return p


def speak(rows, tmax):
    s = [r["peak"] for r in rows.values() if not fell(r, tmax) and r.get("peak")]
    return sum(s) / len(s) if s else float("nan")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    tmax = None
    for i, a in enumerate(sys.argv):
        if a == "--tmax":
            tmax = float(sys.argv[i + 1])
            args = [x for x in args if x != sys.argv[i + 1]]
    base = read(args[0])
    for cp in args[1:]:
        cand = read(cp)
        seeds = sorted(set(base) & set(cand))
        n = len(seeds)
        b = {s: base[s] for s in seeds}
        c = {s: cand[s] for s in seeds}
        fb = {s for s in seeds if fell(b[s], tmax)}
        fc = {s for s in seeds if fell(c[s], tmax)}
        both = fb & fc
        rec = fb - fc
        new = fc - fb
        p = binom_two_sided(len(rec), len(rec) + len(new))
        both_ok = [s for s in seeds if s not in fb and s not in fc and b[s].get("peak") and c[s].get("peak")]
        dpk = sum(c[s]["peak"] - b[s]["peak"] for s in both_ok) / len(both_ok) if both_ok else float("nan")
        print(f"== {cp}  vs  {args[0]}   (n={n} paired seeds{', falls counted before ' + str(tmax) + ' s' if tmax else ''})")
        print(f"   BASE falls {len(fb)} ({100 * len(fb) / n:.1f} %)   CAND falls {len(fc)} ({100 * len(fc) / n:.1f} %)   both {len(both)}  recovered {len(rec)}  new {len(new)}   McNemar p {p:.3f}")
        print(f"   phases  BASE {phases(b, tmax)}  CAND {phases(c, tmax)}")
        print(f"   windows BASE {windows(b, tmax)}  CAND {windows(c, tmax)}")
        print(f"   survivors' mean peak BASE {speak(b, tmax):.3f}  CAND {speak(c, tmax):.3f}   mean paired peak difference (both survive, n={len(both_ok)}) {dpk:+.4f}")
        if len(new) <= 25:
            print("   new falls:", ", ".join(f"{s}@{c[s]['time']:.1f}s" for s in sorted(new)))


if __name__ == "__main__":
    main()
