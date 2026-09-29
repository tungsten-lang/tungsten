#!/usr/bin/env python3
"""Ask TypeSafe's Jev (via OpenRouter) to fill in a GF(2) matrix-multiplication
tensor decomposition coefficient by coefficient, then check it exactly.

  tools/jev_fill_decomposition.py 2x2x2              # one shape at its live best rank
  tools/jev_fill_decomposition.py --all --summary S  # every live shape, JSONL summary
  tools/jev_fill_decomposition.py 3x3x3 --rank 23 --out DIR

Jev returns typed decisions, not text, so every coefficient bit is one `noul`
question (P(bit is 1)). By default the whole scheme goes in one request;
--terms-per-request splits it only when a request would be too large. The
answers are thresholded at 0.5 and the resulting scheme is expanded against
the full target tensor. Reports validity, the residual (tensor entries that
disagree), and how far each term is from the nearest exact reference term.
The key is $OPENROUTER_API_KEY, as for the `jev` CLI.
"""
import argparse, concurrent.futures, json, os, pathlib, sys, time, urllib.error, urllib.request

import numpy as np

URL = os.environ.get("JEV_URL", "https://openrouter.ai/api/v1/systemone")
MODEL = os.environ.get("JEV_MODEL", "jev-latest")

STATE = (
    "Task: fill in an exact bilinear algorithm for {n}x{m} by {m}x{p} "
    "matrix multiplication C = A*B over GF(2) (all arithmetic mod 2, coefficients 0 or 1). "
    "The algorithm has exactly {r} products M1..M{r}. Product Mt = (sum of a chosen subset "
    "of the entries of A) * (sum of a chosen subset of the entries of B), and every entry "
    "C[i][k] is the sum of a chosen subset of the products. Taken together, the {r} "
    "products must reproduce C[i][k] = sum over j of A[i][j]*B[j][k] exactly for every "
    "i and k. Indices are 1-based: A[i][j] has i in 1..{n}, j in 1..{m}; B[j][k] has k in "
    "1..{p}; C[i][k]. {hint}\n\nEach question names one coefficient: 'M3 A[1][2]' asks "
    "whether product M3's A-factor includes A[1][2]; 'M3 B[j][k]' likewise for the "
    "B-factor; 'M3 C[i][k]' asks whether M3 is added into C[i][k]. {span}"
)

HINTS = {
    (2, 2, 2): "The best known algorithm is Strassen's (1969); use its standard numbering "
               "M1..M7: M1=(A11+A22)(B11+B22), and so on as in the textbook.",
    (3, 3, 3): "The best known algorithm is Laderman's (1976) rank-23 algorithm.",
    (4, 4, 4): "The best known algorithm over GF(2) is AlphaTensor's (2022) rank-47 algorithm.",
}


def load_best(home, shape):
    """Live checkpoint -> (n, m, p, U, V, W) as 0/1 uint8 arrays, rows = terms."""
    n, m, p = map(int, shape.split("x"))
    lines = [l for l in (home / "checkpoints/gf2" / shape / "best.txt").read_text().split("\n") if l.strip()]
    if lines[0].startswith("MFW1"):
        terms = [tuple(int(x, 16) for x in l.split()) for l in lines[1:]]
    else:
        terms = [tuple(map(int, l.split())) for l in lines[1:]]
    def unpack(masks, width):
        return np.array([[(x >> i) & 1 for i in range(width)] for x in masks], dtype=np.uint8)
    U, V, W = (unpack([t[f] for t in terms], w) for f, w in enumerate((n*m, m*p, n*p)))
    if residual(n, m, p, U, V, W) != 0:
        # Some checkpoints store C column-major (bit k*n+i); normalize to i*p+k.
        W = W[:, [k*n + i for i in range(n) for k in range(p)]]
    if residual(n, m, p, U, V, W) != 0:
        raise ValueError(f"{shape}: live checkpoint is not an exact scheme")
    return n, m, p, U, V, W


def target(n, m, p):
    T = np.zeros((n*m, m*p, n*p), dtype=np.uint8)
    for i in range(n):
        for j in range(m):
            for k in range(p):
                T[i*m+j, j*p+k, i*p+k] = 1
    return T


def residual(n, m, p, U, V, W):
    """Number of tensor entries where the scheme disagrees with matmul."""
    if len(U) == 0:
        return int(target(n, m, p).sum())
    S = np.zeros((n*m * m*p, n*p), dtype=np.float32)
    for lo in range(0, len(U), 256):  # float32 sums stay exact below 2^24 terms
        u, v, w = (X[lo:lo+256].astype(np.float32) for X in (U, V, W))
        S += (u[:, :, None] * v[:, None, :]).reshape(len(u), -1).T @ w
    S = S.reshape(n*m, m*p, n*p)
    return int(((S.astype(np.int64) & 1) != target(n, m, p)).sum())


def term_questions(n, m, p, t):
    q = {}
    for name, rows, cols in (("A", n, m), ("B", m, p), ("C", n, p)):
        for a in range(rows):
            for b in range(cols):
                q[f"m{t}_{name}{a+1}_{b+1}"] = {"type": "noul", "instructions": f"M{t} {name}[{a+1}][{b+1}]"}
    return q


def post(body, key, tries=4):
    data = json.dumps(body).encode()
    for attempt in range(tries):
        req = urllib.request.Request(URL, data=data, headers={
            "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            if e.code in (429, 500, 502, 503, 504) and attempt + 1 < tries:
                time.sleep(2 ** attempt)
                continue
            raise RuntimeError(f"HTTP {e.code}: {detail[:300]}")
        except (urllib.error.URLError, TimeoutError):
            if attempt + 1 < tries:
                time.sleep(2 ** attempt)
                continue
            raise


def fill(n, m, p, r, key, jobs, out_dir=None, per_request=0):
    hint = HINTS.get((n, m, p), "")
    per = per_request or r
    def one(lo):
        hi = min(lo + per - 1, r)
        span = (f"Fill in all {r} products M1..M{r} at once." if lo == 1 and hi == r
                else f"Fill in products M{lo}..M{hi} of the {r}.")
        questions = {}
        for t in range(lo, hi + 1):
            questions.update(term_questions(n, m, p, t))
        body = {"model": MODEL, "state": STATE.format(n=n, m=m, p=p, r=r, hint=hint, span=span),
                "questions": questions}
        resp = post(body, key)
        if out_dir:
            (out_dir / f"{n}x{m}x{p}.M{lo}-{hi}.json").write_text(json.dumps({"request": body, "response": resp}))
        return resp
    probs, cost, requests = {}, 0.0, 0
    with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
        for resp in pool.map(one, range(1, r + 1, per)):
            probs.update({k: v["noul"] for k, v in resp["answers"].items()})
            cost += resp.get("usage", {}).get("cost", 0.0)
            requests += 1
    def matrix(name, rows, cols):
        return np.array([[probs[f"m{t}_{name}{a+1}_{b+1}"] for a in range(rows) for b in range(cols)]
                         for t in range(1, r + 1)])
    return matrix("A", n, m), matrix("B", m, p), matrix("C", n, p), cost, requests


def nearest_term_distance(U, V, W, RU, RV, RW):
    """Per Jev term: Hamming distance to the closest term of the reference scheme."""
    X = np.hstack([U, V, W]).astype(np.float32)
    R = np.hstack([RU, RV, RW]).astype(np.float32)
    d = X.sum(axis=1)[:, None] + R.sum(axis=1)[None, :] - 2 * (X @ R.T)
    return d.min(axis=1).astype(np.int64)


def run_shape(home, shape, rank, key, jobs, out_dir, per_request=0):
    n, m, p, RU, RV, RW = load_best(home, shape)
    r = rank or len(RU)
    t0 = time.monotonic()
    PU, PV, PW, cost, requests = fill(n, m, p, r, key, jobs, out_dir, per_request)
    U, V, W = ((P >= 0.5).astype(np.uint8) for P in (PU, PV, PW))
    res = residual(n, m, p, U, V, W)
    total = n*m * m*p * n*p
    ones = int(target(n, m, p).sum())
    dist = nearest_term_distance(U, V, W, RU, RV, RW)
    conf = np.concatenate([np.abs(P - 0.5).ravel() * 2 for P in (PU, PV, PW)])
    distinct = len({(a.tobytes(), b.tobytes(), c.tobytes()) for a, b, c in zip(U, V, W)})
    return {
        "shape": shape, "rank": r, "valid": res == 0, "residual": res,
        "target_ones": ones, "tensor_entries": total,
        "empty_scheme_residual": ones,
        "zero_terms": int(sum(1 for a, b, c in zip(U, V, W) if not a.any() or not b.any() or not c.any())),
        "distinct_terms": distinct,
        "exact_reference_terms_reproduced": int((dist == 0).sum()),
        "median_bits_from_nearest_reference_term": float(np.median(dist)),
        "density": float(np.mean(np.concatenate([U.ravel(), V.ravel(), W.ravel()]))),
        "mean_confidence": float(conf.mean()),
        "requests": requests, "cost_usd": round(cost, 6), "seconds": round(time.monotonic() - t0, 1),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("shapes", nargs="*")
    ap.add_argument("--all", action="store_true", help="every live shape, smallest first")
    ap.add_argument("--rank", type=int, default=0, help="rank to ask for (default: live best)")
    ap.add_argument("--home", default=os.environ.get("METAFLIP_HOME", str(pathlib.Path.home() / ".tungsten/metaflip")))
    ap.add_argument("--out", help="keep every request/response JSON here")
    ap.add_argument("--summary", help="append one JSON line per shape here")
    ap.add_argument("--terms-per-request", type=int, default=0,
                    help="split a scheme across requests (default 0: the whole scheme in one request)")
    ap.add_argument("-j", "--jobs", type=int, default=16)
    args = ap.parse_args()
    key = os.environ.get("OPENROUTER_API_KEY") or os.environ.get("OPENROUOTER_API_KEY")
    if not key:
        sys.exit("no key: set OPENROUTER_API_KEY")
    home = pathlib.Path(args.home)
    shapes = args.shapes
    if args.all:
        shapes = [d.name for d in (home / "checkpoints/gf2").iterdir() if (d / "best.txt").exists()]
    def size(s):
        n, m, p = map(int, s.split("x"))
        return int((home / "checkpoints/gf2" / s / "best.txt").read_text().split("\n")[0].split()[-1]) * (n*m + m*p + n*p)
    shapes.sort(key=size)
    out_dir = pathlib.Path(args.out) if args.out else None
    if out_dir:
        out_dir.mkdir(parents=True, exist_ok=True)
    for shape in shapes:
        try:
            row = run_shape(home, shape, args.rank, key, args.jobs, out_dir, args.terms_per_request)
        except Exception as e:
            row = {"shape": shape, "error": str(e)[:300]}
        print(json.dumps(row), flush=True)
        if args.summary:
            with open(args.summary, "a") as f:
                f.write(json.dumps(row) + "\n")


if __name__ == "__main__":
    main()
