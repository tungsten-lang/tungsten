#!/usr/bin/env python3
"""One-off importer: a legacy Profiles episode (screenplay.txt + shots.py + audio/vo alignments, as read by
tools/parse.py, tools/timeline.py and tools/render.py) -> <episode>/studio/episode.json (schema studio.episode/1).

    python3 apps/studio/tools/import_legacy.py ~/videos/profiles-in-mathematics/archimedes-eratosthenes

Everything the legacy pipeline computed at run time from float seconds is re-expressed as integers that the
Tungsten resolver turns into frames and samples:
  * lines chain on the previous line's speech end with an integer gap_ms (GAP_SAME 280 / GAP_CHANGE 450 / 0 after a
    long pause, plus @pause, minus @overlap), exactly the rules of tools/timeline.py;
  * a take's speech window and spoken-word starts are integer ms from its ElevenLabs alignment (the alignment is
    already on a 1 ms grid);
  * a shot starts at an anchor: the first line of its span minus its lead (TIMELINE.md: snap(first line start -
    lead_ms)), or, for shots with no line of their own (title, black, cards, outro), the previous line's end plus
    the pauses before the cut;
  * phrase cues (the i2v start, the triptych panes, the s36 wipe) stay phrases; the resolver finds them in the
    take's word list, so they follow a re-take or a nudge;
  * transitions are frames: round(seconds * 24).
Nothing in the legacy folders is modified; the only output is studio/episode.json."""
import hashlib, json, os, pathlib, re, sys

EP = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").expanduser().resolve()
sys.path.insert(0, str(EP))
sys.path.insert(0, str(EP / "tools"))
import parse  # noqa: E402
from shots import SHOTS  # noqa: E402

FPS = 24
GAP_SAME, GAP_CHANGE = 280, 450
CFG = {s["id"]: s for s in SHOTS}
OUT = EP / "studio" / "episode.json"
OUTRO_WAV = pathlib.Path("/Users/erik/math/openai/videos/channel/outro/out/outro.wav")

# render.py constants
TRANS = {"s01": ("fadein", 1.8), "card:title_end": ("fadein", 1.4), "card:credits": ("dissolve", 1.0),
         "anim:outro": ("dissolve", 0.8)}
FADE_OUT_BEFORE = {"s_black": 1.2}
WIPE_LEN, WIPE_AT = 7.0, "X-ray beams picked out"
PROGRAMS = {"anim:title"}   # shots kept as live Tungsten programs (scenes.w), the rest as their rendered frames


def sha_file(p, cache={}):
    p = pathlib.Path(p)
    if p not in cache:
        h = hashlib.sha256()
        with open(p, "rb") as f:
            for blk in iter(lambda: f.read(1 << 22), b""):
                h.update(blk)
        cache[p] = h.hexdigest()
    return cache[p]


def rel(p):
    p = pathlib.Path(p)
    try:
        return str(p.relative_to(EP))
    except ValueError:
        return str(p)


def frames_asset(d, pattern, first):
    files = sorted(x for x in d.iterdir() if x.suffix in (".png", ".jpg"))
    h = hashlib.sha256()
    for f in files:
        h.update(f"{f.name}:{sha_file(f)}\n".encode())
    return {"kind": "frames", "path": rel(d), "pattern": pattern, "first": first, "count": len(files),
            "sha256": h.hexdigest()}


def ms(x):
    return int(round(float(x) * 1000))


def spoken_word_starts(al):
    """tools/cues.py / srt.py: start of every spoken word, [audio tags] skipped, in ms from the file start."""
    out, in_tag, in_word = [], False, False
    for c, t in zip(al["characters"], al["character_start_times_seconds"]):
        if c == "[":
            in_tag = True
            continue
        if in_tag:
            in_tag = c != "]"
            continue
        if c.isspace():
            in_word = False
        elif not in_word:
            in_word = True
            out.append(ms(t))
    return out


assets, lines, shots, cues, markers = {}, [], [], [], []


def panel_asset(sid):
    cfg = CFG.get(sid)
    if cfg and cfg["model"] == "artifact":
        p = EP / cfg["prompt"]
    else:
        p = next((EP / f"panels/{sid}.{e}" for e in ("png", "jpg") if (EP / f"panels/{sid}.{e}").exists()), None)
    if p is None:
        raise SystemExit(f"no panel for {sid}")
    key = f"panel:{sid}"
    assets[key] = {"kind": "image", "path": rel(p), "sha256": sha_file(p)}
    return key


def image_asset(key, path):
    p = EP / path
    assets[key] = {"kind": "image", "path": rel(p), "sha256": sha_file(p)}
    return key


def audio_asset(key, path, extra=None):
    p = pathlib.Path(path)
    if not p.is_absolute():
        p = EP / p
    a = {"kind": "audio", "path": rel(p), "sha256": sha_file(p)}
    if extra:
        a.update(extra)
    assets[key] = a
    return key


# ---------------------------------------------------------------------------------------------- the timing spine
ev = parse.parse()
prev_line = None          # id of the last line
acc = 0                   # ms of @pause since the previous line's speech end
overlap = 0
last_spk = None
pending = []              # cuts waiting for the next line: (shot id, acc at the cut)
shot_order = []           # (shot id, anchor)
amb_cur = music_cur = None


def here(extra=0):
    """The current clock as an anchor: the previous line's speech end + the pauses since (+ an offset)."""
    if prev_line is None:
        return {"ref": "start", "ms": acc + extra}
    return {"ref": prev_line, "edge": "end", "ms": acc + extra}


n_line = 0
for e in ev:
    k = e["kind"]
    if k == "line":
        stem = e["vo"]
        alj = EP / f"audio/vo/{stem}.mp3.json"
        al = json.load(open(alj))["alignment"]
        st, en, chars = al["character_start_times_seconds"], al["character_end_times_seconds"], al["characters"]
        alnum = [i for i, c in enumerate(chars) if c.isalnum()]
        lead, tail = ms(st[alnum[0]]), ms(en[alnum[-1]])
        take = f"audio:vo/{stem}"
        audio_asset(take, f"audio/vo/{stem}.mp3", {"speech_ms": [lead, tail], "words_ms": spoken_word_starts(al)})
        gap = GAP_SAME if last_spk == e["spk"] else GAP_CHANGE
        if last_spk is None:
            gap = 0
        gap_ms = acc + gap - overlap
        lid = f"L{n_line + 1:03d}"
        n_line += 1
        lines.append({"id": lid, "spk": e["spk"], "text": e["sub"], "take": take,
                      "after": {"ref": prev_line or "start", "gap_ms": gap_ms}, "nudge_ms": 0, "ripple": True})
        for sid, cut_acc in pending:      # cuts placed before this line: anchor them to its start (span head)
            shot_order.append((sid, {"ref": lid, "edge": "start", "ms": cut_acc - gap_ms}, lid))
        pending = []
        prev_line, acc, overlap, last_spk = lid, 0, 0, e["spk"]
    elif k == "pause":
        acc += ms(e["arg"])
        if float(e["arg"]) >= 0.7:
            last_spk = None
    elif k == "overlap":
        overlap = ms(e["arg"])
    elif k in ("cut", "card"):
        sid = e["arg"].strip() if k == "cut" else "card:" + e["arg"].strip()
        pending.append((sid, acc))
    elif k == "super":
        cues.append({"id": f"sup:{len(cues):02d}", "track": "V3", "kind": "super", "text": e["arg"],
                     "at": here(500), "ms": 3800})
    elif k == "sfx":
        a = e["arg"].split()
        off = ms(a[1]) if len(a) > 1 else 0
        db = float(a[2]) if len(a) > 2 else -10.0
        src = audio_asset(f"audio:sfx/{a[0]}", f"audio/sfx/{a[0]}.mp3")
        cues.append({"id": f"sfx:{sum(1 for c in cues if c['kind'] == 'sfx') + 1:02d}", "track": "A5", "kind": "sfx",
                     "name": a[0], "src": src, "at": here(off), "gain_db": db,
                     "filter": "tone" if a[0].startswith("tone_") else "sfx",
                     "shake": a[0] in ("thunder_crack", "anvil_chord", "fire_roar_hit")})
    elif k == "amb":
        a = e["arg"].split()
        if amb_cur:
            amb_cur["to"] = here()
        amb_cur = None
        if a[0] != "off":
            src = audio_asset(f"audio:sfx/amb_{a[0]}", f"audio/sfx/amb_{a[0]}.mp3")
            amb_cur = {"id": f"amb:{sum(1 for c in cues if c['kind'] == 'amb') + 1:02d}", "track": "A4", "kind": "amb",
                       "name": a[0], "src": src, "from": here(), "to": None,
                       "gain_db": float(a[1]) if len(a) > 1 else -22.0}
            cues.append(amb_cur)
    elif k == "music":
        a = e["arg"].split()
        if a[0] == "off":
            if music_cur:
                music_cur["to"] = here()
                music_cur["fade_out_ms"] = ms(a[1]) if len(a) > 1 else 2000
            music_cur = None
        else:
            if music_cur:
                music_cur["to"] = here()
                music_cur["fade_out_ms"] = 2000
            src = audio_asset(f"audio:music/{a[0]}", f"audio/music/{a[0]}.mp3")
            music_cur = {"id": f"mus:{sum(1 for c in cues if c['kind'] == 'music') + 1:02d}", "track": "A3",
                         "kind": "music", "name": a[0], "src": src, "from": here(), "to": None,
                         "gain_db": float(a[1]) if len(a) > 1 else -20.0, "fade_out_ms": 2000}
            cues.append(music_cur)
    else:
        raise SystemExit(f"unknown event {k}")

for sid, cut_acc in pending:              # trailing shots with no line after them
    shot_order.append((sid, {"ref": prev_line, "edge": "end", "ms": cut_acc}, None))
END = here()
for c in (amb_cur, music_cur):
    if c:
        c["to"] = END
if music_cur:
    music_cur["fade_out_ms"] = 3500

# legacy music fade-in: 2.0 s for a cue starting in the first 5 s, else 1.2 s (tools/mix.py)
for c in cues:
    if c["kind"] == "music":
        c["fade_in_ms"] = 2000 if c["from"] == {"ref": "start", "ms": 0} else 1200

# span: the lines whose speech starts inside each shot (metadata for the storyboard; timing comes from `at`)
line_ids = [l["id"] for l in lines]
heads = {sid: head for sid, _, head in shot_order}

# ---------------------------------------------------------------------------------------------- shots (V1)


def trans_for(sid):
    kind, d = TRANS.get(sid, ("dissolve", 0.7 if sid.startswith("anim:") else 0.6))
    if sid.startswith("s_black"):
        return {"kind": "cut", "frames": 0}
    return {"kind": kind, "frames": int(round(d * FPS))}


def bar_for(cfg):
    b = {}
    for key in ("place", "label", "src"):
        if cfg.get(key):
            b[key] = cfg[key]
    if cfg.get("ey") not in ("", None) and cfg.get("sy") not in ("", None):
        b["ey"], b["sy"] = int(cfg["ey"]), int(cfg["sy"])
    return b or None


def phrase(text):
    return {"phrase": text}


def focus(cfg):
    f = cfg.get("focus", (0.5, 0.45))
    return [round(float(f[0]), 6), round(float(f[1]), 6)]


for i, (sid, at, head) in enumerate(shot_order):
    span = []
    claimed = any(h == head for _, _, h in shot_order[i + 1:])   # a later cut before the same line owns it
    if head and not claimed:
        j = line_ids.index(head)
        # the span runs until the next shot's head line (exclusive)
        later = [h for _, _, h in shot_order[i + 1:] if h]
        stop = line_ids.index(later[0]) if later else len(line_ids)
        span = [head, line_ids[stop - 1]] if stop > j else [head, head]
    sh = {"id": sid, "at": at, "span": span, "trans_in": trans_for(sid)}
    cfg = CFG.get(sid, {})
    if sid.startswith("s_black"):
        sh["kind"] = "black"
    elif sid.startswith("card:"):
        sh["kind"] = "card"
        sh["card"] = sid[5:]
        sh["style"] = "card"
    elif sid in PROGRAMS:
        # rendered from its Tungsten source through its program hash, not from the pre-rendered PNGs
        aid = sid[5:]
        sh["kind"] = "program"
        sh["program"] = {"source": "scenes.w", "module": aid, "data": [f"data/cues_{aid}.csv"]}
    elif sid.startswith("anim:"):
        aid = sid[5:]
        sh["kind"] = "frames"
        key = f"anim:{aid}"
        assets[key] = frames_asset(EP / f"anim_frames/{aid}", "%05d.png", 0)
        sh["src"] = key
    elif cfg.get("model") == "triptych":
        sh["kind"] = "group"
        sh["layout"] = "triptych"
        sh["style"] = "novel"
        sh["children"] = []
        for k, ((psid, plbl), pat) in enumerate(zip(cfg["panes"], cfg["pane_at"])):
            child = {"id": f"{sid}/{psid}", "src": panel_asset(psid), "label": plbl,
                     "pane": [k * (628 + 18), 0, 628, 804]}
            if pat:
                child["at"] = phrase(pat)
            sh["children"].append(child)
        sh["camera"] = {"move": "drift"}
        sh["bar"] = bar_for(cfg)
    else:
        sh["kind"] = "still"
        sh["style"] = "novel"
        if cfg.get("model") == "wipe":
            sh["src"] = image_asset(f"image:{sid}_a", cfg["srcs"][0])
            sh["wipe"] = {"src": image_asset(f"image:{sid}_b", cfg["srcs"][1]), "at": phrase(WIPE_AT),
                          "ms": int(WIPE_LEN * 1000), "default_ms": 6000}
        else:
            sh["src"] = panel_asset(sid)
        sh["camera"] = {"move": cfg.get("move", "push"), "focus": focus(cfg)}
        if cfg.get("flip"):
            sh["camera"]["flip"] = True
        sh["fx"] = list(cfg.get("fx", []))
        if cfg.get("i2v"):
            clip = EP / f"clips/{sid}_frames"
            if clip.exists():
                ck = f"clip:{sid}"
                assets[ck] = frames_asset(clip, "%04d.jpg", 1)
                sh["kind"] = "clip"
                sh["clip"] = {"src": ck, "fps": 24, "min_speed": 0.8, "max_speed": 1.0, "blend": True,
                              "xf_in_ms": 500}
                if cfg["i2v"].get("at"):
                    sh["clip"]["at"] = phrase(cfg["i2v"]["at"])
        bar = bar_for(cfg)
        if bar:
            sh["bar"] = bar
    shots.append(sh)

# fade-out-before (render.py FADE_OUT_BEFORE): the outgoing picture fades to black before the named shot (V4)
for sid, d in FADE_OUT_BEFORE.items():
    cues.append({"id": f"fade:{sid}", "track": "V4", "kind": "fade_out", "before": sid,
                 "frames": int(round(d * FPS)), "power": 1.2})

# outro audio: the channel outro's own soundtrack starts with the anim:outro shot (tools/mix.py)
if OUTRO_WAV.exists() and any(s["id"] == "anim:outro" for s in shots):
    cues.append({"id": "aud:outro", "track": "A6", "kind": "audio", "src": audio_asset("audio:outro", OUTRO_WAV),
                 "at": {"shot": "anim:outro"}, "gain_db": 0, "norm": {"rms_db": -19.0},
                 "fade_in_ms": 50, "fade_out_ms": 250})

# chapters: youtube.md's list, each at the shot that starts at that second (TIMELINE.md: chapter = the chapter
# shot's first frame, floored to the second)
legacy = json.load(open(EP / "render/timeline.json"))
yt = (EP / "youtube/youtube.md").read_text().split("Chapters:", 1)[1]
for ln in yt.splitlines():
    m = re.match(r"^(\d+):(\d\d) (.+)$", ln.strip())
    if not m:
        if markers and ln.strip() == "":
            break
        continue
    sec = int(m.group(1)) * 60 + int(m.group(2))
    hit = [s["id"] for s in legacy["shots"] if int(s["start"]) == sec]
    if not hit:
        raise SystemExit(f"chapter {ln!r}: no shot starts at {sec}s")
    markers.append({"id": f"ch:{len(markers) + 1:02d}", "kind": "chapter", "title": m.group(3), "at": hit[0]})

# outro captions (tools/srt.py), in ms from the anim:outro shot's start
captions = [{"at": {"shot": "anim:outro"}, "from_ms": a, "to_ms": b, "text": t} for a, b, t in [
    (0, 2267, "Hit like, if you enjoyed the video."),
    (2481, 4590, "Subscribe, if you want the next one."),
    (5161, 6337, "Or don't."),
    (6337, 10954, "[DIRECTOR] Cut! Cut! I need you to really hit the like and…")]]

# ---------------------------------------------------------------------------------------------- styles
styles = {
    "novel": {
        "active": [0, 138, 1920, 804],
        "grade": {"shadow_tint": [-0.022, 0.014, 0.032], "highlight_tint": [0.042, 0.015, -0.030],
                  "contrast_mix": 0.20, "saturation": 0.94, "lift": 0.02, "gain": 0.965,
                  "bloom": {"threshold": 0.68, "down": 8, "sigma": 5, "tint": [0.26, 0.11, 0.04]}},
        "vignette": {"amount": 0.30, "x": 0.7, "y": 0.9, "clip": 1.6, "power": 1.4},
        "grain": {"count": 10, "sigma": 0.7, "base": 0.020, "mid": 0.045},
        "jitter_px": 0.30,
        "bars": {"family": "Avenir Next", "weight": "bold", "place_size": 22, "label_size": 21, "gap_size": 19,
                 "pane_size": 20},
        "super": {"family": "Baskerville", "size": 34, "cps_ms": 42, "fade_ms": 600},
    },
    "card": {"paper_seed": 3, "family": "Baskerville"},
}

cards = {
    "title_end": {"layout": "title", "kicker": "PROFILES IN MATHEMATICS", "title": "ARCHIMEDES & ERATOSTHENES",
                  "subtitle": "THE SAND-RECKONER AND THE SIEVE"},
    "credits": {"layout": "credits", "rows": [
        ["SERIES", "Profiles in Mathematics"],
        ["MATHEMATICAL ANIMATION", "Tungsten"],
        ["FORMAL VERIFICATION", "Satori (149 theorems checked)"],
        ["GRAPHIC NOVEL PANELS", "Nano Banana 2  ·  Seedream 4"],
        ["MOTION CLIPS", "Seedance 2.5"],
        ["VOICES, SCORE & SOUND", "ElevenLabs"],
        ["ARCHIMEDES PALIMPSEST IMAGES", "© the owner of the Archimedes Palimpsest, CC BY 3.0"],
        ["WALL PAINTING", "Giulio Parigi, Uffizi (1599–1600), public domain"]]},
}
for s in shots:
    if s["kind"] == "card":
        s["layout"] = cards[s["card"]]

# narration voice chains (tools/mix.py VO_FX): kept as data, interpreted by `studio mix`
warm = [["peak", 3300, 1.2, -3.5], ["peak", 5800, 1.0, -6.5], ["peak", 7800, 1.0, -6.5], ["deesser", 0.6, 0.5, 0.5],
        ["lowpass", 8200, 0.707], ["compressor", -20, 2.0, 20, 220, 1.0]]


def chain(hp, f, g):
    return [["highpass", hp, 0.707], ["peak", f, 1.0, g]] + warm


voices = {
    "NARRATOR": {"chain": chain(65, 145, 1.8), "pan": [1.0, 1.0], "reverb": [450, 0.04, 1500], "gain_db": 0.0},
    "ARCHIMEDES": {"chain": chain(60, 125, 2.0), "pan": [0.95, 1.0], "reverb": [1000, 0.10, 1400], "gain_db": 0.3},
    "ERATOSTHENES": {"chain": chain(75, 150, 1.8), "pan": [1.0, 0.94], "reverb": [850, 0.09, 1400], "gain_db": 0.2},
    "HIERON": {"chain": chain(65, 135, 2.0), "pan": [1.0, 0.92], "reverb": [1000, 0.10, 1400], "gain_db": 0.3},
    "MARCELLUS": {"chain": chain(70, 140, 1.8), "pan": [0.92, 1.0], "reverb": [850, 0.09, 1400], "gain_db": 0.2},
    "CICERO": {"chain": chain(75, 150, 1.6), "pan": [1.0, 0.94], "reverb": [750, 0.09, 1400], "gain_db": 0.0},
    "SOLDIER": {"chain": chain(70, 140, 1.8), "pan": [0.94, 1.0], "reverb": [600, 0.07, 1400], "gain_db": 0.2},
}
mix = {
    "voices": voices,
    "vo": {"rms_db": -20.0, "max_gain_db": 14.0, "deess": {"cross_hz": 3400, "max_ratio": 0.18, "abs_db": -31.0}},
    "music": {"chain": [["peak", 3200, 1.2, -3.5], ["lowpass", 6000, 0.707]], "rms_db": -20.0, "offset_db": 8.0,
              "loop_xf_ms": 1500},
    "amb": {"chain": [["highpass", 45, 0.707], ["lowpass", 1100, 0.707], ["lowpass", 1400, 0.707]], "rms_db": -22.0,
            "max_gain_db": 8.0, "offset_db": 6.0, "pre_ms": 500, "post_ms": 1000, "fade_ms": 1000},
    "sfx": {"chain": [["lowpass", 2200, 0.707], ["peak", 1600, 1.2, -7.0], ["highshelf", 2400, 0.5, -12.0]],
            "peak_db": -4.0, "max_gain_db": 10.0, "fade_in_ms": 5, "fade_out_ms": 150},
    "tone": {"chain": [["lowpass", 1500, 0.707]], "rms_db": -19.0, "max_gain_db": 6.0},
    "duck": {"block": 64, "attack_ms": 30, "release_ms": 450, "full": 0.04, "music_db": -6.5, "amb_db": -3.5},
    "peak_db": -1.5,
}

episode = {
    "schema": "studio.episode/1",
    "id": "profiles/archimedes-eratosthenes",
    "title": "Archimedes & Eratosthenes: The Sand-Reckoner and the Sieve",
    "root": "..",
    "seed": 1000,
    "imported": {"from": "screenplay.txt + shots.py + audio/vo/*.json via tools/parse.py", "by": "import_legacy.py"},
    "cuts": {"full": {"w": 1920, "h": 1080, "rate": [24, 1], "sr": 48000, "tc_start": "00:00:00:00", "colour": "bt709",
                      "end": END, "picture": {"active": [0, 138, 1920, 804]},
                      "loudness": {"lufs": -16, "tp": -1.5}}},
    "assets": assets,
    "styles": styles,
    "mix": mix,
    "lines": lines,
    "shots": shots,
    "cues": cues,
    "captions": captions,
    "markers": markers,
}
OUT.parent.mkdir(exist_ok=True)
OUT.write_text(json.dumps(episode, indent=1, ensure_ascii=False) + "\n")
print(f"wrote {OUT}: {len(lines)} lines, {len(shots)} shots, {len(cues)} cues, {len(markers)} chapters, "
      f"{len(assets)} assets")
