#!/usr/bin/env python3
"""Per-shot SSIM: the rebuilt picture against the shipped master, at the same item-local frames.

    python3 compare_ssim.py <episode dir> <mine: master.mp4 | fresh> [--shots s01,s12] [--per 3] [--keep]

For each shot, samples `per` local frames spread over its main part (outside its incoming transition and away from
its end), decodes the shipped master at legacy_f0 + k (BT.601 matrix: render.py piped untagged RGB into ffmpeg,
whose default RGB->YUV is BT.601) and the rebuild at f0 + k (BT.709, as tagged), and computes SSIM on luma (Rec.601
weights on the decoded RGB, 11x11 gaussian window, sigma 1.5). `fresh` renders the rebuild's frames with
`studio frame --fresh` instead of decoding a master. Writes studio/reports/ssim.json."""
import json, math, os, pathlib, subprocess, sys, tempfile
import numpy as np
from PIL import Image

EP = pathlib.Path(sys.argv[1]).expanduser()
MINE = sys.argv[2]
args = sys.argv[3:]
shots_only = None
per = 3
keep = "--keep" in args
if "--shots" in args:
    shots_only = set(args[args.index("--shots") + 1].split(","))
if "--per" in args:
    per = int(args[args.index("--per") + 1])
STUDIO = os.environ.get("STUDIO_BIN", "/Users/erik/tungsten-worktrees/engine/apps/studio/bin/studio")
R = json.load(open(EP / "studio/build/full/timeline.resolved.json"))
T = json.load(open(EP / "render/timeline.json"))
LEGACY = EP / "render/Archimedes_Eratosthenes.mp4"
OUT = EP / "studio/samples/ssim"
OUT.mkdir(parents=True, exist_ok=True)


def legacy_frame(start):
    f = int(math.floor(start * 24))
    while f / 24 < start:
        f += 1
    while f > 0 and (f - 1) / 24 >= start:
        f -= 1
    return f


def decode(path, n, matrix, out):
    t0 = max(0.0, (n - 24) / 24 - 0.5 / 24)
    first = int(math.ceil(t0 * 24 - 1e-9))
    sel = n - first
    vf = f"select=eq(n\\,{sel}),scale=in_color_matrix={matrix}:in_range=tv:out_range=pc:flags=accurate_rnd+full_chroma_int,format=rgb24"
    subprocess.check_call(["ffmpeg", "-nostdin", "-y", "-v", "error", "-ss", f"{t0:.6f}", "-i", str(path), "-vf", vf,
                           "-fps_mode", "passthrough", "-frames:v", "1", str(out)])
    return np.asarray(Image.open(out).convert("RGB"), np.float64)


def luma(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def gauss_filter(x, sigma=1.5, rad=5):
    k = np.exp(-(np.arange(-rad, rad + 1) ** 2) / (2 * sigma * sigma))
    k /= k.sum()
    y = np.apply_along_axis(lambda r: np.convolve(r, k, mode="same"), 1, x)
    return np.apply_along_axis(lambda c: np.convolve(c, k, mode="same"), 0, y)


def ssim(a, b):
    a, b = luma(a), luma(b)
    C1, C2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    mu_a, mu_b = gauss_filter(a), gauss_filter(b)
    saa = gauss_filter(a * a) - mu_a ** 2
    sbb = gauss_filter(b * b) - mu_b ** 2
    sab = gauss_filter(a * b) - mu_a * mu_b
    m = ((2 * mu_a * mu_b + C1) * (2 * sab + C2)) / ((mu_a ** 2 + mu_b ** 2 + C1) * (saa + sbb + C2))
    return float(m[6:-6, 6:-6].mean())


v1 = R["tracks"][0]["items"]
rows = []
for it, sh in zip(v1, T["shots"]):
    if shots_only and it["id"] not in shots_only:
        continue
    n = it["f1"] - it["f0"]
    tin = it["trans_in"].get("frames", 0)
    a, b = min(tin + 2, n - 1), max(min(tin + 2, n - 1), n - 16)
    ks = sorted(set(int(a + (b - a) * (i + 0.5) / per) for i in range(per)))
    lf0 = legacy_frame(sh["start"])
    vals = []
    for k in ks:
        tag = f"{it['id'].replace(':', '_')}_{k:05d}"
        # same absolute frame: both pictures then sit within half a frame of the same instant (comparing the same
        # local frame would put the legacy content up to a whole frame ahead where its cut was rounded up)
        legacy = decode(LEGACY, it["f0"] + k, "bt601", OUT / f"{tag}_legacy.png")
        if MINE == "fresh":
            p = OUT / f"{tag}_mine.png"
            subprocess.check_call([STUDIO, "frame", str(EP / "studio/episode.json"), str(it["f0"] + k), "--fresh", "--png",
                                   str(p)], stdout=subprocess.DEVNULL)
            mine = np.asarray(Image.open(p).convert("RGB"), np.float64)
        else:
            mine = decode(MINE, it["f0"] + k, "bt709", OUT / f"{tag}_mine.png")
        s = ssim(legacy, mine)
        vals.append({"k": k, "frame": it["f0"] + k, "legacy_local": it["f0"] + k - lf0, "ssim": round(s, 4)})
        if not keep:
            for suf in ("_legacy.png", "_mine.png"):
                (OUT / (tag + suf)).unlink(missing_ok=True)
    m = sum(v["ssim"] for v in vals) / len(vals)
    rows.append({"id": it["id"], "kind": it["kind"], "mean": round(m, 4), "min": min(v["ssim"] for v in vals),
                 "samples": vals})
    print(f"{it['id']:>16} {it['kind']:>7}  mean {m:.4f}  min {min(v['ssim'] for v in vals):.4f}  "
          + " ".join(f"{v['ssim']:.3f}" for v in vals), flush=True)
(EP / "studio/reports").mkdir(parents=True, exist_ok=True)
name = "ssim.json" if not shots_only else "ssim_partial.json"
json.dump({"mine": MINE, "per": per, "shots": rows}, open(EP / "studio/reports" / name, "w"), indent=1)
low = [r for r in rows if r["mean"] < 0.9]
allm = [v["ssim"] for r in rows for v in r["samples"]]
print(f"{len(rows)} shots, {len(allm)} samples: mean {sum(allm) / len(allm):.4f}, median {sorted(allm)[len(allm) // 2]:.4f}; "
      f"{len(low)} shots below 0.9: {' '.join(r['id'] for r in low)}")
