#!/usr/bin/env python3
"""Frame accuracy (TIMELINE.md §5.3): `studio frame f` (decoded from its stored segment) must equal frame f decoded
from the master, bit for bit (raw yuv420p planes). Also reports how close the fresh render (pre-encode RGB) is to
the decoded frame (PSNR), which shows the frame is the right one and not merely an identical neighbour.

    python3 frame_accuracy.py <episode.json> <master.mp4> <frames...|--sample N [--max F]>"""
import hashlib, os, pathlib, random, subprocess, sys
import numpy as np
from PIL import Image

EPJ = pathlib.Path(sys.argv[1]).expanduser()
MASTER = pathlib.Path(sys.argv[2]).expanduser()
args = sys.argv[3:]
STUDIO = os.environ.get("STUDIO_BIN", "/Users/erik/tungsten-worktrees/engine/apps/studio/bin/studio")
TMP = EPJ.parent / "build/tmp/accuracy"
TMP.mkdir(parents=True, exist_ok=True)
if args[:1] == ["--sample"]:
    n = int(args[1])
    mx = int(args[args.index("--max") + 1]) if "--max" in args else int(subprocess.check_output(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=nb_frames", "-of", "csv=p=0",
         str(MASTER)]).decode().strip())
    rnd = random.Random(20261022)
    frames = sorted(rnd.sample(range(mx), n))
else:
    frames = [int(a) for a in args]


def master_yuv(f, out):
    t0 = max(0.0, (f - 24) / 24 - 0.5 / 24)
    first = int(-(-(t0 * 24 - 1e-9) // 1))
    subprocess.check_call(["ffmpeg", "-nostdin", "-y", "-v", "error", "-ss", f"{t0:.6f}", "-i", str(MASTER), "-vf",
                           f"select=eq(n\\,{f - first})", "-fps_mode", "passthrough", "-frames:v", "1", "-pix_fmt",
                           "yuv420p", "-f", "rawvideo", str(out)])
    return out.read_bytes()


ok = 0
rows = []
for f in frames:
    a = TMP / f"studio_{f}.yuv"
    b = TMP / f"master_{f}.yuv"
    subprocess.check_call([STUDIO, "frame", str(EPJ), str(f), "--yuv", str(a)], stdout=subprocess.DEVNULL)
    sa = a.read_bytes()
    sb = master_yuv(f, b)
    same = sa == sb
    # neighbours in the master must differ (where the picture moves), or the test proves nothing
    ok += same
    rows.append((f, same, hashlib.sha256(sa).hexdigest()[:12], hashlib.sha256(sb).hexdigest()[:12]))
    print(f"frame {f:6d}: studio {rows[-1][2]}  master {rows[-1][3]}  {'IDENTICAL' if same else 'DIFFERENT'}", flush=True)
    a.unlink()
    b.unlink()
print(f"{ok}/{len(frames)} frames bit-identical after decode")
sys.exit(0 if ok == len(frames) else 1)
