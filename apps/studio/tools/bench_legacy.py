#!/usr/bin/env python3
"""Time the legacy Python/PIL + libx264 renderer on a frame span, exactly as tools/render.py's render_chunk does
(same Renderer, same ffmpeg command), writing under studio/build/bench/ only (render/ is never touched).

    python3 bench_legacy.py <episode dir> <f0> <f1>      # one call per <= 400-frame lock hold

Seeds the FX like render_chunk (1000 + f0 // 400)."""
import json, pathlib, subprocess, sys, time

EP = pathlib.Path(sys.argv[1]).expanduser().resolve()
f0, f1 = int(sys.argv[2]), int(sys.argv[3])
sys.path.insert(0, str(EP / "tools"))
sys.path.insert(0, str(EP))
import render  # noqa: E402  (the episode's tools/render.py)

T = json.load(open(EP / "render/timeline.json"))
out = EP / f"studio/build/bench/legacy_{f0:06d}_{f1:06d}.mp4"
out.parent.mkdir(parents=True, exist_ok=True)
t0 = time.time()
R = render.Renderer(T, seed=1000 + f0 // render.CHUNK)
t1 = time.time()
p = subprocess.Popen([
    "ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{render.OW}x{render.OH}", "-r",
    str(render.FPS), "-i", "-", "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
    "-x264-params", "keyint=48", str(out)], stdin=subprocess.PIPE)
for fi in range(f0, f1):
    p.stdin.write(R.frame(fi))
p.stdin.close()
if p.wait() != 0:
    raise SystemExit("ffmpeg failed")
t2 = time.time()
print(f"legacy {f0}..{f1}: {f1 - f0} frames, setup {t1 - t0:.2f} s, render+encode {t2 - t1:.2f} s, "
      f"{(f1 - f0) / (t2 - t0):.2f} fps -> {out}", flush=True)
