#!/usr/bin/env python3
"""The Tungsten animations, all modules at once: scenes.w (tools/build_scenes.py) compiled with the media worktree's
Tungsten, then every animation's frames rendered by the compiled program in parallel frame ranges, into
anim_frames/<id>/%05d.png (the frame sequences studio/episode.json shows).

    python3 tools/tw_anims.py [--jobs 10] [--only "m01 m11"] [--force]      (inside ONE heavy hold: tools/tw_render.sh)
    python3 tools/tw_anims.py still <id> <seconds> <out.png>                one frame, for checking

Caching: each animation keeps anim_frames/<id>/.key = SHA-256 of what its frames depend on (anim/core.w, its module
and the modules it calls, the generated dispatcher, the data files the modules read, its duration and the compiler).
An animation whose key is unchanged and whose frames are all there is skipped; a changed one is cleared and rendered
again. The compiled program is keyed the same way (render/scenes_bin.key). Prints one timing line per stage."""
import concurrent.futures as cf
import csv, hashlib, json, os, pathlib, re, subprocess, sys, time

EP = pathlib.Path(os.environ.get("TW_FILM_ROOT", str(pathlib.Path(sys.argv[0]).absolute().parent.parent)))
CFG = json.loads((EP / "tools/tw.json").read_text())
TW = pathlib.Path(os.environ.get("STUDIO_TW", CFG["tungsten"])).expanduser()
BIN = EP / "render/scenes_bin"
FPS = 24
args = sys.argv[1:]


def opt(name, default):
    return args[args.index(name) + 1] if name in args else default


def sha_bytes(*parts):
    h = hashlib.sha256()
    for p in parts:
        h.update(p if isinstance(p, bytes) else str(p).encode())
        h.update(b"\0")
    return h.hexdigest()


def compiler_id():
    c = TW / "bin/tungsten-compiler"
    st = c.stat()
    return f"{c}:{st.st_size}:{st.st_mtime_ns}"


def build_program():
    """scenes.w from anim/ (fast), then the compile when its text or the compiler changed."""
    t0 = time.time()
    mods = os.environ.get("TW_MODULES", "").split()       # a subset (helpers + finished modules) while others are written
    subprocess.check_call([sys.executable, str(EP / "tools/build_scenes.py")] + mods, stdout=subprocess.DEVNULL)
    key = sha_bytes((EP / "scenes.w").read_bytes(), compiler_id())
    kf = EP / "render/scenes_bin.key"
    if BIN.exists() and kf.exists() and kf.read_text().strip() == key:
        print(f"anims: program up to date ({time.time() - t0:.1f} s)", flush=True)
        return key
    part = BIN.with_name("scenes_bin.part")
    log = EP / "render/tungsten/scenes_compile.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    with open(log, "w") as lf:
        r = subprocess.call([str(TW / "bin/tungsten"), "-o", str(part), str(EP / "scenes.w")], cwd=TW, stdout=lf,
                            stderr=subprocess.STDOUT)
    if r != 0:
        raise SystemExit(f"scenes.w compile failed: {log}")
    part.rename(BIN)
    kf.write_text(key + "\n")
    print(f"anims: compiled scenes.w in {time.time() - t0:.1f} s", flush=True)
    return key


def module_deps():
    """Each module's own file plus the modules whose definitions it calls (m02b draws with m02's helpers)."""
    A = EP / "anim"
    mods = {p.stem: p.read_text() for p in A.glob("*.w") if p.stem != "core"}
    defs = {m: set(re.findall(r"^-> ([A-Za-z_0-9?!]+)", t, re.M)) for m, t in mods.items()}
    deps = {}
    for m, t in mods.items():
        d = {m}
        for o, ds in defs.items():
            if o != m and any(re.search(r"(?<![A-Za-z0-9_])" + re.escape(x) + r"(?![A-Za-z0-9_?!])", t) for x in ds - defs[m]):
                d.add(o)
        deps[m] = d
    changed = True
    while changed:                 # transitive
        changed = False
        for m in deps:
            more = set().union(*(deps[x] for x in deps[m])) - deps[m]
            if more:
                deps[m] |= more
                changed = True
    return deps


def anim_key(aid, dur, deps, prog_key):
    A = EP / "anim"
    sw = (EP / "scenes.w").read_text()
    disp = sw[sw.index("# Dispatcher & CLI"):]
    # the dispatcher's shared code only: its branch list (which modules are compiled in) does not change a frame
    disp = "\n".join(l for l in disp.splitlines()
                     if not re.match(r'\s*(if|elsif) anim_id == "', l) and not re.match(r"\s*draw_[A-Za-z0-9_]+\(svg, db, t, len\)", l))
    parts = [A.joinpath("core.w").read_bytes(), disp, dur, compiler_id()]
    for m in sorted(deps.get(aid, {aid})):
        parts += [m, A.joinpath(f"{m}.w").read_bytes()]
    data = [EP / f"data/wb/{aid}.tsv", EP / "data/satori_raw.txt", EP / f"data/cues_{aid}.csv", EP / f"data/words_{aid}.csv", EP / "research/dating_bands.csv",
            EP / f"data/dl/{aid}.tsv"]          # The Mandate of Heaven: each animation's display list (tools/dl_build.py)
    data += sorted((EP / "data").glob("map_*.csv"))
    # The Wisdom of Egypt: glyph outlines, embedded photos and the shared timeline registry are inputs too
    data += [EP / "data/glyphs.tsv", EP / "data/photos.tsv"] + sorted((EP / "data/photos").glob("*.b64"))
    data += sorted((EP.parent / "shared/timeline").glob("*.csv"))
    # The Wisdom of Mesopotamia: every shared data file a module may read (glyphs, photos, acrostic, local timeline rows,
    # each agent's own tables) is an input; other animations' cue and word files are not.
    data += sorted(p for p in (EP / "data").glob("*.tsv") if p.name not in ("glyphs.tsv", "photos.tsv"))
    data += sorted(p for p in (EP / "data").glob("*.csv") if not p.name.startswith(("cues_", "words_", "anim_durations")))
    # Zarathustra: the pre-shaped Avestan / Old Persian / Hebrew strings (tools/script_glyphs.py) and the photo crops
    data += sorted((EP / "data/glyphs").glob("*.b64")) + sorted((EP / "data").glob("text_*.tsv"))
    data += [EP / "data/glyphs/index.tsv"] if (EP / "data/glyphs/index.tsv").exists() else []
    data += sorted((EP / "panels/src/anim").glob("*.jpg")) if (EP / "panels/src/anim").exists() else []
    for p in data:
        if p.exists():
            parts += [p.name, p.read_bytes()]
    return sha_bytes(*parts)


def run_range(aid, dur, f0, f1):
    t0 = time.time()
    r = subprocess.run([str(BIN), "scene", str(EP), aid, dur, str(f0), str(f1)], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"{aid} {f0}..{f1} failed: {r.stdout[-400:]} {r.stderr[-400:]}")
    return aid, f0, f1, time.time() - t0


def main():
    if args[:1] != ["still"]:
        for gate in CFG.get("gates", []):
            match = re.search(gate["pattern"], (EP / gate["file"]).read_text(), re.M)
            equal = gate.get("equal")
            if not match or (equal and match.group(equal[0]) != match.group(equal[1])):
                raise SystemExit(f"anims: gate failed: {gate['file']} {gate['pattern']}")
    if args[:1] == ["still"]:
        aid, t, out = args[1], float(args[2]), args[3]
        build_program()
        dur = {r["id"]: r["dur"] for r in csv.DictReader(open(EP / "data/anim_durations.csv"))}[aid]
        subprocess.check_call([str(BIN), "still", str(EP), aid, dur, str(t), out])
        return
    jobs = int(opt("--jobs", "10"))
    only = set(opt("--only", "").split())
    force = "--force" in args
    T0 = time.time()
    prog_key = build_program()
    t_compile = time.time() - T0
    deps = module_deps()
    todo, keys = [], {}
    for r in csv.DictReader(open(EP / "data/anim_durations.csv")):
        aid, dur = r["id"], r["dur"]
        if only and aid not in only:
            continue
        nf = int(round(float(dur) * FPS))
        d = EP / f"anim_frames/{aid}"
        key = anim_key(aid, dur, deps, prog_key)
        kf = d / ".key"
        complete = all((d / f"{f:05d}.png").exists() for f in range(nf)) and not (d / f"{nf:05d}.png").exists()
        if not force and kf.exists() and kf.read_text().strip() == key and complete:
            continue
        d.mkdir(parents=True, exist_ok=True)
        for p in d.glob("*.png"):          # a changed animation starts clean (no stale frames past its new end)
            p.unlink()
        kf.unlink(missing_ok=True)
        keys[aid] = (key, nf)
        todo.append((aid, dur, nf))
    if not todo:
        print(f"anims: nothing to render ({time.time() - T0:.1f} s)", flush=True)
        return
    # frame ranges of <= CH frames, longest animations first, so the pool stays full to the end
    CH = int(opt("--chunk", "60"))
    tasks = []
    for aid, dur, nf in sorted(todo, key=lambda x: -x[2]):
        for f0 in range(0, nf, CH):
            tasks.append((aid, dur, f0, min(nf, f0 + CH) - 1))
    nfr = sum(nf for _, _, nf in todo)
    t1 = time.time()
    left = {aid: 0 for aid, _, _ in todo}
    for aid, _, _, _ in tasks:
        left[aid] += 1
    busy = 0.0
    with cf.ThreadPoolExecutor(jobs) as ex:
        futs = [ex.submit(run_range, *t) for t in tasks]
        for fu in cf.as_completed(futs):
            aid, f0, f1, dt = fu.result()
            busy += dt
            left[aid] -= 1
            if left[aid] == 0:
                (EP / f"anim_frames/{aid}/.key").write_text(keys[aid][0] + "\n")
    dt = time.time() - t1
    print(f"anims: {nfr} frames of {len(todo)} animations ({' '.join(a for a, _, _ in todo)}) in {dt:.1f} s "
          f"with {jobs} workers ({nfr / dt:.1f} fps, {busy:.0f} worker-s); compile/check {t_compile:.1f} s; "
          f"total {time.time() - T0:.1f} s", flush=True)


if __name__ == "__main__":
    main()
