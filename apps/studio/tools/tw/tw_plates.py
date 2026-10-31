#!/usr/bin/env python3
"""The background plates that de-band the animations and the Short's cards (2026-10-26, Erik: "very jagged"):
    anim/bg_rsvg.png    anim/core.w background()'s radial gradient exactly as rsvg draws it (8-bit, one code every ~60 px)
    anim/bg_dither.png  the same gradient computed in floating point and dithered (tools/tw_bg.w, static +-1 code noise)
    short/bg_rsvg.png, short/bg_dither.png   the same for short/short.w's s_bg (1080 x 1920)
The studio engine swaps every frame pixel that still equals bg_rsvg (pure background, untouched by any content) for the
dithered plate's (episode.json "replace" on the animation shots); tools/tw_short.w does the same for the Short's cards.
The gradient is read from the Tungsten sources, so a changed background is noticed: tw_bg.w draws only these stops.
    python3 tools/tw_plates.py           (re-made when the sources or tw_bg.w change; tools/tw_render.sh and tw_short.sh run it)"""
import hashlib, json, os, pathlib, re, subprocess, sys

EP = pathlib.Path(os.environ.get("TW_FILM_ROOT", str(pathlib.Path(sys.argv[0]).absolute().parent.parent)))
TW = pathlib.Path(os.environ.get("STUDIO_TW", json.loads((EP / "tools/tw.json").read_text())["tungsten"])).expanduser()
SOURCE = pathlib.Path(__file__).resolve().parent / "tw_bg.w"
BG = EP / "render/tungsten/tw_bg"
STOPS = ['stop-color="#131b2c"', 'stop-color="#090d15"', 'stop-color="#04060a"']


def grad(path, fn):
    s = path.read_text()
    i = s.index(f"-> {fn}(svg)")
    j = s.index('svg.raw("', i) + len('svg.raw("')
    k = j
    while not (s[k] == '"' and s[k - 1] != "\\"):     # the string literal's closing quote (\" are escaped quotes)
        k += 1
    g = s[j:k].replace('\\"', '"')
    if "<radialGradient" not in g:
        raise SystemExit(f"{path.name} {fn}(): no radial gradient found")
    for st in STOPS:
        if st not in g:
            raise SystemExit(f"{path.name} {fn}(): the gradient's stops changed ({g}); update tools/tw_bg.w")
    cx, cy, r = (float(re.search(k + r'="([0-9.]+)%"', g).group(1)) / 100 for k in ("cx", "cy", "r"))
    mid = float(re.findall(r'offset="([0-9.]+)"', g)[1])
    return g, cx, cy, r, mid


def make(name, src, fn, w, h, outdir):
    g, cx, cy, r, mid = grad(src, fn)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{g}'
           f'<rect x="0" y="0" width="{w}" height="{h}" fill="url(#{re.search(r"id=.([a-z_]+)", g).group(1)})"/></svg>')
    key = hashlib.sha256((svg + SOURCE.read_text()).encode()).hexdigest()
    kf = outdir / "bg_plates.key"
    if kf.exists() and kf.read_text().strip() == key and (outdir / "bg_rsvg.png").exists() and (outdir / "bg_dither.png").exists():
        return False
    tmp = outdir / "bg_rsvg.svg"
    tmp.write_text(svg)
    subprocess.check_call(["rsvg-convert", "-z", "1", "-o", str(outdir / "bg_rsvg.png"), str(tmp)])
    tmp.unlink()
    subprocess.check_call([str(BG), str(outdir / "bg_dither.png"), str(w), str(h), str(cx), str(cy), str(r), str(mid)],
                          stdout=subprocess.DEVNULL)
    kf.write_text(key + "\n")
    print(f"plates: {name} {w}x{h} cx {cx} cy {cy} r {r} mid {mid} -> {outdir.relative_to(EP)}/bg_rsvg.png, bg_dither.png")
    return True


def main():
    src = SOURCE
    if not BG.exists() or src.stat().st_mtime > BG.stat().st_mtime:
        subprocess.check_call([str(TW / "bin/tungsten"), "-o", str(BG), str(src)], cwd=TW, stdout=subprocess.DEVNULL)
    a = make("film", EP / "anim/core.w", "background", 1920, 1080, EP / "anim")
    b = make("short", EP / "short/short.w", "s_bg", 1080, 1920, EP / "short") if (EP / "short/short.w").exists() else False
    if not (a or b):
        print("plates: up to date")


if __name__ == "__main__":
    main()
