#!/usr/bin/env python3
"""Build the robolab abilities page (progress.html) and print its file map.

    .venv/bin/python site/progress/build_progress.py                  # writes site/progress/progress.html
    .venv/bin/python site/progress/build_progress.py --files          # also prints every video's source path (JSON)
    .venv/bin/python site/progress/build_progress.py --publish        # prints the `files` map for the Artifact tool:
                                                                      #   new videos -> path, unreferenced ones -> null
    .venv/bin/python site/progress/build_progress.py --mark-published # records the videos the live page now holds

The page is one HTML file plus the videos it references. It shows each ability's best result, its newest
videos (each with a "Copy link" to its public file on thecompanygardener.yaks.app/robolab) and how it got there.
The videos are embedded from the artifact's own files (the viewer only plays media it hosts) and uploaded a second time to
the yaks app, so a link works for people who cannot open the private artifact.
Numbers in the board and the charts are read from playground/arena/champions.json, so they follow the arena;
the prose carries dated statements and is edited by hand here. Status, goals, agents and arena mechanics
live in README.md and HANDOFF_*.md, not on the page.
Design: the same tokens, type and row layout as the earlier progress page (Barlow Semi Condensed / IBM Plex).
"""
import html
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CHAMPS = json.load(open(os.path.join(ROOT, "playground/arena/champions.json")))
CODEX_ROOT = "/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/"
CODEX = CODEX_ROOT + "results-page/dist/assets/"
ARTIFACT_URL = "https://claude.ai/artifact/CjykjapusLk3wsktyAbg7T"
PUBLIC_VIDEO_BASE = "https://thecompanygardener.yaks.app/robolab/"   # every video is also a public file here (video/mp4, byte ranges)
PUBLISHED = os.path.join(HERE, "published.json")

UPDATED = time.strftime("%-d %b %Y, %-I:%M %p").replace("AM", "am").replace("PM", "pm")


def F(trial):
    """A champion's mean over the rollouts that passed their guards, as `arena.py board` prints it.

    Failed guards and crashes score +-1e9, which is why summary.mean alone is not the metric.
    """
    ok = [x for x in CHAMPS[trial].get("scores", []) if abs(x) < 1e8]
    return sum(ok) / len(ok) if ok else float("nan")


def scores_ok(trial):
    return [x for x in CHAMPS[trial].get("scores", []) if abs(x) < 1e8]


def V(trial, nd=2):
    return f"{F(trial):.{nd}f}"


def passes(trial):
    c = CHAMPS[trial]
    n = len(c.get("scores", [])) or c["summary"]["n"]
    return f"{sum(1 for x in c.get('scores', []) if abs(x) < 1e8)} of {n}"


def num(v):
    """Two decimals, trailing zeros trimmed: 7.02, 8.2, 33, 22.9."""
    return f"{v:.2f}".rstrip("0").rstrip(".")


def e(s):
    return html.escape(s, quote=True)


def md(s):
    """Escape, then **bold** and `code`."""
    s = e(s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"`(.+?)`", r'<span class="mono">\1</span>', s)
    return s


# ---------------------------------------------------------------- videos ---------
VIDEOS = {}  # published name -> source path


def mp4_size(path):
    """(width, height) from the first video sample entry; None if the file is missing or odd."""
    import struct
    try:
        d = open(path, "rb").read()
    except OSError:
        return None
    pos = 0
    while True:
        i = d.find(b"stsd", pos)
        if i < 0:
            return None
        if d[i + 16:i + 20] in (b"avc1", b"hvc1", b"hev1", b"av01", b"vp09"):
            return struct.unpack(">HH", d[i + 44:i + 48])
        pos = i + 4


def video_id(name):
    """The anchor a video's "Copy link" points at. Only letters, digits . _ ~ - survive in a shared link's hash."""
    return "v-" + re.sub(r"[^A-Za-z0-9._~-]", "_", os.path.splitext(name)[0])


def vid(name, src, label, caption=None):
    """One video with its caption and a "Copy link" button (the link is ARTIFACT_URL#<video id>)."""
    VIDEOS[name] = src
    vid_id = video_id(name)
    cap = f'<span class="cap">{md(caption)}</span>' if caption else '<span class="cap"></span>'
    wh = mp4_size(src)
    ar = f' style="aspect-ratio: {wh[0]} / {wh[1]}"' if wh else ""
    return (f'<figure class="media" id="{vid_id}"><video src="{e(name)}" controls muted loop playsinline preload="metadata"{ar} '
            f'aria-label="{e(label)}"></video><figcaption>{cap}'
            f'<button type="button" class="copy" data-id="{vid_id}" data-url="{e(PUBLIC_VIDEO_BASE + name)}" aria-label="Copy link to this video: {e(label)}">Copy link</button>'
            f'</figcaption></figure>')


def out(name):
    return os.path.join(ROOT, "out", name)


# ---------------------------------------------------------------- chips ----------
# Only labels that change how a number should be read: no status.
CHIP = {
    "tuned": ("study", "Tuned to one start"),
    "labelled": ("prov", "Labelled body variant"),
    "ext": ("study", "Policy from Codex"),
    "athlete": ("prov", "Athlete body"),
}


def chip(kind, text=None):
    cls, default = CHIP[kind]
    return f'<span class="chip {cls}">{e(text or default)}</span>'


# ---------------------------------------------------------------- tables ---------
def table(head, rows, wide=False):
    """rows: list of lists; a cell starting with '#' is a number cell."""
    th = "".join(f"<th>{md(h)}</th>" for h in head)
    body = []
    for r in rows:
        tds = []
        for c in r:
            if isinstance(c, str) and c.startswith("#"):
                tds.append(f'<td class="n">{md(c[1:])}</td>')
            else:
                tds.append(f"<td>{md(c)}</td>")
        body.append(f"<tr>{''.join(tds)}</tr>")
    w = " wide" if wide else ""
    return f'<div class="tablewrap"><table class="{w.strip()}"><tr>{th}</tr>{"".join(body)}</table></div>'


def steps(rows, head=("When", "Best", "What changed")):
    """The progression of one result: rows of (when, value, what changed)."""
    th = "".join(f"<th>{e(h)}</th>" for h in head)
    body = "".join(f'<tr><td class="when">{e(w)}</td><td class="n">{md(v)}</td><td>{md(t)}</td></tr>' for w, v, t in rows)
    return f'<div class="tablewrap"><table class="steps"><tr>{th}</tr>{body}</table></div>'


def bests(items):
    """Big numbers at the top of a card: (value, what it is)."""
    return '<div class="bests">' + "".join(f'<div><b>{e(v)}</b><span>{e(t)}</span></div>' for v, t in items) + '</div>'


# ---------------------------------------------------------------- charts ---------
def contrast(a, b):
    def lum(h):
        h = h.lstrip("#")
        r, g, bl = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
        f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(bl)
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def chart(cid, title, unit, axis_max, ticks, rows, note, legend_ours="Robolab"):
    """Horizontal bars, one row per result.

    rows: dict(label, sub, value, kind, tip, nd) with kind in
    ours (solid accent) | variant (hatched accent: a labelled body, not comparable) |
    study (outline: open-loop program) | ref (grey: people, challenge winners).
    """
    used = {r["kind"] for r in rows}
    pct = lambda v: 100.0 * v / axis_max
    grid = "".join(f'<i class="cgrid" style="left:{pct(t):.2f}%"></i>' for t in ticks)
    axis = "".join(f'<span style="left:{pct(t):.2f}%">{num(t)}</span>' for t in ticks)
    lines, trs = [], []
    kind_txt = {"ours": "robolab", "variant": "labelled body", "study": "open-loop program", "ref": "people / winners"}
    for r in rows:
        v, k = r["value"], r["kind"]
        fv = (lambda x, nd=r["nd"]: f"{x:.{nd}f}") if r.get("nd") is not None else num
        pc = "%" if unit == "%" else ""
        shown = r.get("shown") or f'<b>{fv(v)}{pc}</b>'
        if k == "ours":
            marks = f'<span class="cbar" style="width:{pct(v):.2f}%"></span>'
        elif k == "variant":
            marks = f'<span class="cbar variant" style="width:{pct(v):.2f}%"></span>'
        elif k == "study":
            marks = f'<span class="ctrack study" style="width:{pct(v):.2f}%"></span>'
        else:
            marks = f'<span class="cbar ref" style="width:{pct(v):.2f}%"></span>'
        tip_v = f'{fv(v)}{pc}' if pc else f'{fv(v)} {unit}'
        lines.append(
            f'<div class="crow" tabindex="0" data-l="{e(r["label"])}" data-v="{e(tip_v)}" data-n="{e(r.get("tip", ""))}">'
            f'<div class="clabel">{e(r["label"])}<small>{e(r.get("sub", ""))}</small></div>'
            f'<div class="cplot">{grid}{marks}<span class="cval" style="left:calc({pct(v):.2f}% + 8px)">{shown}</span></div></div>')
        trs.append(f'<tr><td>{e(r["label"])}<br><small>{e(r.get("sub", ""))}</small></td><td class="n">{tip_v}</td>'
                   f'<td>{kind_txt[k]}</td><td>{e(r.get("tip", ""))}</td></tr>')
    legend = []
    if "ours" in used:
        legend.append(f'<span><i class="sw ours"></i>{e(legend_ours)}</span>')
    if "variant" in used:
        legend.append('<span><i class="sw variant"></i>Labelled body variant, not comparable</span>')
    if "study" in used:
        legend.append('<span><i class="sw study"></i>Open-loop program, reflexes off</span>')
    if "ref" in used:
        legend.append('<span><i class="sw ref"></i>People or challenge winners</span>')
    return f'''<figure class="chart" id="{cid}">
  <div class="chead"><h3>{e(title)}</h3><button type="button" class="tbtn" aria-pressed="false" data-target="{cid}">Table</button></div>
  <div class="legend">{"".join(legend)}</div>
  <div class="cview">
    <div class="cbody">{"".join(lines)}
      <div class="caxis"><div class="cspacer"></div><div class="cticks">{axis}</div></div>
    </div>
  </div>
  <div class="tview" hidden><div class="tablewrap"><table class="wide"><tr><th>Row</th><th>Value</th><th>Kind</th><th>Note</th></tr>{"".join(trs)}</table></div></div>
  <figcaption class="note">{md(note)}</figcaption>
</figure>'''


# ---------------------------------------------------------------- cards ----------
def card(cid, title, best, media, paras, tbl=None, body=None, chips=(), gallery=False):
    ch = f'<div class="chips">{" ".join(chips)}</div>' if chips else ""
    text = "".join(f"<p>{md(p)}</p>" for p in paras)
    bl = f'<p class="bodyline"><b>Body.</b> {md(body)}</p>' if body else ""
    cls = "skill gallery" if gallery else "skill"
    return f'''<article class="{cls}" id="{cid}">
  <div class="mediacol">{"".join(media)}</div>
  <div class="side"><h3>{e(title)}</h3>{ch}{bests(best)}{text}{tbl or ""}{bl}</div>
</article>'''


def small(cid, title, media, text, chips=()):
    ch = f'<div class="chips">{" ".join(chips)}</div>' if chips else ""
    return (f'<article class="model" id="{cid}"><h3>{e(title)}</h3>{ch}{media}'
            f'<p class="note">{md(text)}</p></article>')


CSS = r"""
:root {
  --bg: #F2F4F6; --surface: #FFFFFF; --ink: #17202A; --muted: #5A6774; --rule: #D6DCE2; --soft: #E6EAEE;
  --accent: #C9432C; --ok: #2E7A4E; --ok-soft: #DDEFE4; --run: #9A6512; --run-soft: #F5EAD4;
  --info: #24608F; --info-soft: #DCEAF5; --ref: #8794A1;
  --display: "Barlow Semi Condensed", "Arial Narrow", system-ui, sans-serif;
  --body: "IBM Plex Sans", system-ui, -apple-system, sans-serif;
  --mono: "IBM Plex Mono", ui-monospace, "SF Mono", Menlo, monospace;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    color-scheme: dark;
    --bg: #0F151B; --surface: #172029; --ink: #E5EBF0; --muted: #94A2AF; --rule: #2A3642; --soft: #232F3A;
    --accent: #EF6A4E; --ok: #62C28E; --ok-soft: #173327; --run: #E3AE52; --run-soft: #362A15;
    --info: #86B7E4; --info-soft: #17293A; --ref: #6E7D8B;
  }
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --bg: #0F151B; --surface: #172029; --ink: #E5EBF0; --muted: #94A2AF; --rule: #2A3642; --soft: #232F3A;
  --accent: #EF6A4E; --ok: #62C28E; --ok-soft: #173327; --run: #E3AE52; --run-soft: #362A15;
  --info: #86B7E4; --info-soft: #17293A; --ref: #6E7D8B;
}
* { box-sizing: border-box; }
body { background: var(--bg); color: var(--ink); font: 15px/1.55 var(--body); padding-inline: 20px; padding-block: 28px 64px; }
.wrap { max-width: 1120px; margin: 0 auto; display: grid; gap: 44px; }
h1, h2, h3 { font-family: var(--display); font-weight: 700; letter-spacing: 0.01em; text-wrap: balance; margin: 0; line-height: 1.1; }
h1 { font-size: clamp(30px, 5vw, 44px); }
h2 { font-size: clamp(24px, 3.4vw, 32px); }
h3 { font-size: 22px; }
p { margin: 0; max-width: 70ch; }
a { color: var(--info); }
.lede { color: var(--muted); font-size: 16px; }
.eyebrow { font: 600 12px/1 var(--body); letter-spacing: 0.12em; text-transform: uppercase; color: var(--muted); }
.head, section { display: grid; gap: 16px; min-width: 0; }
.board { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; }
@media (min-width: 900px) { .board { grid-template-columns: repeat(4, minmax(0, 1fr)); } }
.slot { background: var(--surface); border: 1px solid var(--rule); border-radius: 8px; padding: 12px 14px 13px; display: grid; gap: 5px; align-content: start; color: inherit; text-decoration: none; }
a.slot:hover { border-color: var(--muted); }
a.slot:focus-visible, .crow:focus-visible, .tbtn:focus-visible, .copy:focus-visible, video:focus-visible { outline: 2px solid var(--info); outline-offset: 2px; }
.slot .name { font: 600 16px/1.1 var(--display); letter-spacing: 0.03em; text-transform: uppercase; color: var(--muted); }
.slot .best { font: 700 30px/1 var(--display); display: flex; align-items: baseline; gap: 6px; flex-wrap: wrap; font-variant-numeric: tabular-nums; }
.slot .best small { font: 500 12.5px/1 var(--mono); color: var(--muted); }
.slot .num { font: 400 12.5px/1.4 var(--body); color: var(--muted); }
.chips { display: flex; flex-wrap: wrap; gap: 6px; }
.chip { justify-self: start; font: 600 11px/1 var(--body); letter-spacing: 0.08em; text-transform: uppercase; padding: 5px 8px; border-radius: 999px; white-space: nowrap; }
.chip.study { color: var(--info); background: var(--info-soft); }
.chip.prov { color: var(--muted); background: transparent; box-shadow: inset 0 0 0 1px var(--muted); }
.skill { display: grid; grid-template-columns: minmax(0, 1.3fr) minmax(0, 1fr); gap: 22px; align-items: start; padding-top: 22px; border-top: 1px solid var(--rule); scroll-margin-top: 16px; }
@media (max-width: 900px) { .skill { grid-template-columns: 1fr; } }
.mediacol { display: grid; gap: 14px; min-width: 0; }
.skill.gallery { grid-template-columns: repeat(auto-fit, minmax(min(100%, 330px), 1fr)); gap: 18px 22px; }
.skill.gallery .mediacol { display: contents; }
.media { margin: 0; display: grid; gap: 6px; min-width: 0; align-content: start; scroll-margin-top: 20px; border-radius: 8px; }
.media.flash { outline: 3px solid var(--info); outline-offset: 5px; }
.media figcaption { display: flex; flex-wrap: wrap; align-items: flex-start; justify-content: space-between; gap: 4px 14px; font-size: 12.5px; color: var(--muted); }
.media .cap { flex: 1 1 240px; min-width: 0; }
.copy { flex: none; font: 600 12.5px/1.3 var(--body); color: var(--info); background: none; border: 0; padding: 0; cursor: pointer; text-decoration: underline; text-underline-offset: 3px; white-space: nowrap; }
.copy:hover { color: var(--ink); }
.copy.done { color: var(--ok); text-decoration: none; }
.linkbox { flex: 1 1 100%; font: 400 12px/1.3 var(--mono); color: var(--ink); background: var(--surface); border: 1px solid var(--rule); border-radius: 6px; padding: 5px 8px; min-width: 0; }
video { width: 100%; max-width: 100%; border-radius: 6px; background: #0b0f13; display: block; aspect-ratio: 960 / 544; }
.side { display: grid; gap: 12px; min-width: 0; align-content: start; }
.side p { color: var(--muted); font-size: 14px; }
.side p.bodyline { font-size: 12.5px; }
.bests { display: grid; grid-template-columns: repeat(auto-fit, minmax(132px, 1fr)); gap: 10px 18px; }
.bests div { display: grid; gap: 3px; min-width: 0; align-content: start; }
.bests b { font: 700 30px/1 var(--display); color: var(--ink); font-variant-numeric: tabular-nums; }
.bests span { font-size: 12.5px; line-height: 1.35; color: var(--muted); }
.tablewrap { overflow-x: auto; background: var(--surface); border: 1px solid var(--rule); border-radius: 8px; max-width: 100%; }
table { border-collapse: collapse; width: 100%; font-size: 13.5px; }
th, td { text-align: left; padding: 7px 10px; border-bottom: 1px solid var(--rule); vertical-align: top; }
th { font-size: 12px; color: var(--muted); font-weight: 600; letter-spacing: 0.04em; }
td small { color: var(--muted); }
td.n { font-family: var(--mono); font-variant-numeric: tabular-nums; white-space: nowrap; }
td.when { color: var(--muted); white-space: nowrap; font-size: 12.5px; }
.steps td.n { text-align: right; }
.steps th:nth-child(2) { text-align: right; }
tr:last-child td { border-bottom: 0; }
.wide { min-width: 640px; }
.side table { font-size: 13px; }
.side th, .side td { padding: 7px 8px; }
.model { background: var(--surface); border: 1px solid var(--rule); border-radius: 8px; padding: 18px; display: grid; gap: 10px; align-content: start; min-width: 0; scroll-margin-top: 16px; }
.mono { font-family: var(--mono); font-size: 13px; }
.cols { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 18px; }
ul.list { margin: 0; padding-left: 20px; display: grid; gap: 6px; font-size: 14px; max-width: 78ch; }
.note { font-size: 13px; color: var(--muted); }
/* charts */
.chartgrid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 480px), 1fr)); gap: 18px; }
.chart { margin: 0; background: var(--surface); border: 1px solid var(--rule); border-radius: 8px; padding: 16px 18px 14px; display: grid; gap: 10px; align-content: start; min-width: 0; }
.chead { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
.chead h3 { font-size: 20px; }
.tbtn { font: 600 12px/1 var(--body); color: var(--muted); background: transparent; border: 1px solid var(--rule); border-radius: 6px; padding: 6px 10px; cursor: pointer; }
.tbtn:hover { color: var(--ink); border-color: var(--muted); }
.legend { display: flex; flex-wrap: wrap; gap: 6px 16px; font-size: 12.5px; color: var(--muted); }
.legend span { display: inline-flex; align-items: center; gap: 6px; }
.sw { width: 14px; height: 10px; display: inline-block; border-radius: 0 3px 3px 0; }
.sw.ours { background: var(--accent); }
.sw.variant { background: repeating-linear-gradient(135deg, var(--accent) 0 2px, transparent 2px 4px); box-shadow: inset 0 0 0 1.5px var(--accent); }
.sw.study { box-shadow: inset 0 0 0 1.5px var(--accent); }
.sw.ref { background: var(--ref); }
.cbody { position: relative; display: grid; gap: 8px; padding-top: 6px; }
.crow { display: grid; grid-template-columns: minmax(96px, 30%) 1fr; align-items: center; gap: 10px; min-height: 30px; border-radius: 6px; }
.crow:hover { background: var(--soft); }
.clabel { font-size: 13px; line-height: 1.25; }
.clabel small { display: block; color: var(--muted); font-size: 11.5px; }
.cplot { position: relative; height: 22px; margin-right: 104px; }
.cgrid { position: absolute; top: -4px; bottom: -4px; width: 0; border-left: 1px solid var(--rule); }
.cbar, .ctrack { position: absolute; left: 0; top: 50%; transform: translateY(-50%); border-radius: 0 4px 4px 0; }
.cbar { height: 12px; background: var(--accent); }
.cbar.ref { background: var(--ref); }
.cbar.variant { height: 14px; background: repeating-linear-gradient(135deg, var(--accent) 0 2px, transparent 2px 4px); box-shadow: inset 0 0 0 1.5px var(--accent); }
.ctrack { height: 16px; box-shadow: inset 0 0 0 1.5px var(--accent); border-radius: 0 5px 5px 0; }
.cval { position: absolute; top: 50%; transform: translateY(-50%); font: 500 12.5px/1 var(--mono); color: var(--muted); white-space: nowrap; background: var(--surface); padding: 2px 3px; border-radius: 3px; }
.cval b { color: var(--ink); font-weight: 600; }
.caxis { display: grid; grid-template-columns: minmax(96px, 30%) 1fr; gap: 10px; }
.cticks { position: relative; height: 18px; margin-right: 104px; font: 500 11px/1 var(--mono); color: var(--muted); }
.cticks span { position: absolute; transform: translateX(-50%); }
#tip { position: fixed; z-index: 20; pointer-events: none; background: var(--surface); color: var(--ink); border: 1px solid var(--rule); border-radius: 8px; padding: 9px 11px; max-width: 260px; font-size: 12.5px; box-shadow: 0 6px 22px rgba(0,0,0,.18); }
#tip b { display: block; font: 600 15px/1.2 var(--mono); }
#tip span { display: block; color: var(--muted); }
@media (max-width: 560px) { .crow, .caxis { grid-template-columns: 1fr; gap: 2px; } .caxis .cspacer { display: none; } .cplot { margin-top: 2px; } }
@media (prefers-reduced-motion: reduce) { * { scroll-behavior: auto !important; } }
"""

JS = r"""
(function () {
  var BASE = '__ARTIFACT_URL__';
  // play a video only while it is on screen
  var vids = document.querySelectorAll('video');
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (en) {
        try { if (en.isIntersecting && en.intersectionRatio > 0.5) { var p = en.target.play(); if (p && p.catch) p.catch(function () {}); } else { en.target.pause(); } } catch (x) {}
      });
    }, { threshold: [0, 0.5, 1] });
    vids.forEach(function (v) { io.observe(v); });
  }
  // "Copy link": the video's public address (a file on thecompanygardener.yaks.app/robolab); the artifact's own
  // address plus #<video id> also scrolls to that video and plays it, for people who can open the artifact
  function fallbackCopy(text) {
    var ta = document.createElement('textarea');
    ta.value = text; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.top = '0'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select();
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (x) {}
    document.body.removeChild(ta);
    return ok;
  }
  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      try {
        return navigator.clipboard.writeText(text).then(function () { return true; }, function () { return fallbackCopy(text); });
      } catch (x) {}
    }
    return Promise.resolve(fallbackCopy(text));
  }
  function showManual(btn, url) {
    var box = document.createElement('input');
    box.type = 'text'; box.readOnly = true; box.value = url; box.className = 'linkbox';
    box.setAttribute('aria-label', 'Link to this video');
    btn.parentNode.replaceChild(box, btn);
    box.focus(); box.select();
  }
  document.querySelectorAll('.copy').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var url = btn.dataset.url || (BASE + '#' + btn.dataset.id);
      copyText(url).then(function (ok) {
        if (!ok) { showManual(btn, url); return; }
        btn.textContent = 'Link copied'; btn.classList.add('done');
        setTimeout(function () { btn.textContent = 'Copy link'; btn.classList.remove('done'); }, 2200);
      });
    });
  });
  function goHash() {
    var id = '';
    try { id = decodeURIComponent((location.hash || '').slice(1)); } catch (x) {}
    var el = id ? document.getElementById(id) : null;
    if (!el) return;
    el.scrollIntoView({ block: 'center' });
    if (el.classList.contains('media')) {
      el.classList.add('flash');
      setTimeout(function () { el.classList.remove('flash'); }, 2800);
      var v = el.querySelector('video');
      if (v) { try { var p = v.play(); if (p && p.catch) p.catch(function () {}); } catch (x) {} }
    }
  }
  window.addEventListener('hashchange', goHash);
  if (document.readyState === 'complete') { setTimeout(goHash, 60); } else { window.addEventListener('load', function () { setTimeout(goHash, 60); }); }
  // chart tooltips (values also live in the table view)
  var tip = document.getElementById('tip');
  function show(row, x, y) {
    tip.textContent = '';
    var b = document.createElement('b'); b.textContent = row.dataset.v; tip.appendChild(b);
    var l = document.createElement('span'); l.textContent = row.dataset.l; tip.appendChild(l);
    if (row.dataset.n) { var n = document.createElement('span'); n.textContent = row.dataset.n; tip.appendChild(n); }
    tip.hidden = false;
    var w = tip.offsetWidth, h = tip.offsetHeight;
    tip.style.left = Math.max(8, Math.min(window.innerWidth - w - 8, x + 14)) + 'px';
    tip.style.top = Math.max(8, Math.min(window.innerHeight - h - 8, y + 14)) + 'px';
  }
  document.querySelectorAll('.crow').forEach(function (r) {
    r.addEventListener('pointermove', function (ev) { show(r, ev.clientX, ev.clientY); });
    r.addEventListener('pointerleave', function () { tip.hidden = true; });
    r.addEventListener('focus', function () { var q = r.getBoundingClientRect(); show(r, q.left + q.width / 2, q.top); });
    r.addEventListener('blur', function () { tip.hidden = true; });
  });
  // chart <-> table twin
  document.querySelectorAll('.tbtn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var fig = document.getElementById(btn.dataset.target);
      var showTable = btn.getAttribute('aria-pressed') !== 'true';
      btn.setAttribute('aria-pressed', String(showTable));
      btn.textContent = showTable ? 'Chart' : 'Table';
      fig.querySelector('.cview').hidden = showTable;
      fig.querySelector('.tview').hidden = !showTable;
    });
  });
})();
""".replace("__ARTIFACT_URL__", ARTIFACT_URL)


def build():
    # colour check for the chart marks against both surfaces (>= 3:1 for marks)
    for name, fg, bg in (("accent/light", "#C9432C", "#FFFFFF"), ("accent/dark", "#EF6A4E", "#172029"),
                         ("ref/light", "#8794A1", "#FFFFFF"), ("ref/dark", "#6E7D8B", "#172029"),
                         ("link/light", "#24608F", "#F2F4F6"), ("link/dark", "#86B7E4", "#0F151B")):
        assert contrast(fg, bg) >= 3.0, (name, contrast(fg, bg))

    streak_max = int(max(scores_ok("dribble_btl_streak_25")))
    btl_n = len(scores_ok("dribble_btl_streak_25"))
    bal_off = int(round(sum(scores_ok("soccer_single_leg_310_40"))))      # bal1_300 is 1 when the hold reaches 300 s
    bal_off_n = len(CHAMPS["soccer_single_leg_310_40"].get("scores", []))
    bal_ng = int(round(sum(scores_ok("soccer_single_leg_310_40_ng"))))
    bal_ng_n = len(CHAMPS["soccer_single_leg_310_40_ng"].get("scores", []))
    tt300 = 100 * F("tt_p2_300")
    v4p95, v4avg, v4e2, v4sp = (F("sprint_top_speed_v4_p95"), F("sprint_top_speed_v4"), F("sprint_top_speed_v4_elite2"),
                                F("sprint_top_speed_v4_sprinter"))
    v4bd = F("sprint_top_speed_v4_beyond")           # the labelled beyond-human body

    # ------------------------------------------------------------ board -------------
    # (anchor, name, big number, unit, one line under it)
    board_items = [
        ("run-natural", "Natural running", "7.3°", "off human running", "12 starts, 11 stay up"),
        ("sprint", "Sprint", f"{v4p95:.2f}", "m/s", f"95th-percentile body · labelled bodies: {v4sp:.2f} and {v4bd:.2f}"),
        ("blocks", "Sprint from blocks", V("sprint_blocks_30", 2), "s to 30 m", "Bolt ran 3.78 s"),
        ("longjump", "Long jump", V("long_jump_v4_p95", 3), "m", f"tuned to one start · {V('long_jump_p95_robust')} m mean of 16 starts"),
        ("standing", "Standing jump", V("search_jump_legal", 3), "m", f"legal jump · {V('search_jump_robust_legal', 3)} m over 32 starts"),
        ("hurdles", "Hurdles", "0.762", "m", "first hurdle cleared on 4 of 8 starts"),
        ("bat", "Baseball swing", V("bat_power_fresh_rep", 1), "m/s", f"24 held-out pitches, all hit · athlete body"),
        ("dribble", "Dribbling", V("dribble_crossover_25", 2), "crossovers in 15 s", f"through the legs: {streak_max} in a row · basic dribble: {V('dribble', 0)} bounces"),
        ("tt", "Table tennis", f"{tt300:.0f}%", "of phase-2 serves", "phase 1: 100%"),
        ("balance", "One-leg balance", f"{bal_off} of {bal_off_n}", "hold 5 min", "official trial · 37 of 37 more fresh starts"),
        ("soccer", "Penalty kick", "100%", "of phase-1 starts", "phase 2: 0 of 100"),
        ("relocate", "Relocate", V("relocate_p2eval_official", 3), "", "official score, evaluation environment"),
        ("chase", "Chase tag", V("chase_p1", 2), "", f"phase 1 · phase 2: {V('chase_p2', 2)}"),
        ("walk", "Walking", V("walk_stride", 2), "m steps", "at about 1.45 m/s"),
        ("baoding", "Baoding balls", V("baoding_p2", 3), "", "phase-2 score"),
        ("die", "Die and bimanual", V("die_p2_progress", 2), "rad of die turned", f"bimanual stages {V('bimanual_stages', 2)}"),
    ]
    board = "".join(
        f'<a class="slot" href="#{i}"><span class="name">{e(n)}</span>'
        f'<span class="best">{e(b)}{f"<small>{e(u)}</small>" if u else ""}</span><span class="num">{e(t)}</span></a>'
        for i, n, b, u, t in board_items)

    # ------------------------------------------------------------ charts ------------
    ch_sprint = chart(
        "c-sprint", "Sprint speed", "m/s", 15, [0, 3, 6, 9, 12],
        [
            dict(label="Labelled beyond-human body", sub="strength ×2.4, speed ×2.0", value=v4bd, kind="variant",
                 tip="A LABELLED body that is not human (strength ×2.4, muscle speed ×2.0, tendon ×1.5, activation ×0.8: an invented stretch, ideal-control ceiling 16.3 m/s), so never comparable with the other rows. "
                     f"{passes('sprint_top_speed_v4_beyond')} arena starts stay up for 30 s and every one of them peaks above 10.1 m/s; 14 to 26 of each 80 unseen standing starts fall. It takes about 140 m to reach 10 m/s."),
            dict(label="Labelled sprinter body", sub="stronger than a human", value=v4sp, kind="variant",
                 tip="A LABELLED stronger body (strength ×1.55, muscle speed ×1.45, tendon ×1.5, activation ×0.8), fixed from the literature before any runner ran on it, so never comparable with the other rows. "
                     f"{passes('sprint_top_speed_v4_sprinter')} test starts stay up for 30 s."),
            dict(label="95th pct., five gears", sub="29 Sep · calibrated body", value=v4p95, kind="ours",
                 tip="Standing start, 12 perturbed starts. A crouched start, longer strides above 6.5, 7.0 and 7.7 m/s, and an extended-stance gear above 7.8 m/s."),
            dict(label="95th pct., two gears", sub="29 Sep · calibrated body", value=7.449, kind="ours",
                 tip="The first runner with gears: one for accelerating, one for cruising."),
            dict(label="95th pct., re-tuned", sub="28 Sep · older body", value=F("sprint_top_speed_p95"), kind="ours",
                 tip="Reciprocal inhibition and full prime-mover drives, tuned on the older body model."),
            dict(label="95th pct., first sprinter", sub="27 Sep · older body", value=5.966, kind="ours",
                 tip="The 27 Sep walking-pace runner re-tuned on the 95th-percentile body."),
            dict(label="Elite (literature)", sub="calibrated body · three gears", value=v4e2, kind="ours",
                 tip=f"{passes('sprint_top_speed_v4_elite2')} test starts stay up. Every part of this profile is cited; its knee and ankle extensors sit near the untrained mean."),
            dict(label="Average adult", sub="calibrated body · three gears", value=v4avg, kind="ours", tip="A bent-knee gait found from the 95th-percentile search."),
            dict(label="Recreationally active adults", sub="reference", value=7.8, kind="ref",
                 tip="7.3–8.3 m/s: Lazarczuk et al. 2025 (7.77 ± 0.86, mixed group) and Clark, Meng & Stearne 2020 (8.23)"),
            dict(label="Trained sprinters", sub="reference", value=9.9, kind="ref", tip="9.90 ± 0.46 m/s, 79 sprinters (Miyashiro et al. 2019)"),
            dict(label="Usain Bolt", sub="reference", value=12.34, kind="ref",
                 tip="12.34 m/s over 60–80 m of his 9.58 s run (Mackala & Mero 2013). Elite sprinters run 11.5–12.3 m/s."),
        ],
        "Peak speed over one second from a standing start, mean of 12 perturbed starts (the labelled body: the starts that stay up).")

    ch_jump = chart(
        "c-jump", "Long jump", "m", 10, [0, 2, 4, 6, 8, 10],
        [
            dict(label="95th pct., calibrated body", sub="one start · tuned to it", value=F("long_jump_v4_p95"), kind="ours", nd=3,
                 tip="The two-gear runner's own take-off state; the take-off and landing programs are tuned to this exact start, so it is a best case, not a typical jump."),
            dict(label="95th pct., older body", sub="one start · tuned to it", value=F("long_jump_p95"), kind="ours", nd=3,
                 tip="The start its take-off and landing were designed from."),
            dict(label="95th pct., older body", sub="mean of 16 perturbed starts", value=F("long_jump_p95_robust"), kind="ours",
                 tip="Near-open-loop take-off and landing programs that hold up over perturbed starts."),
            dict(label="95th pct., calibrated body", sub="mean of 32 fresh starts", value=F("long_jump_v4_p95_robust32"), kind="ours", nd=2,
                 tip="Starts never used in tuning: 31 of 32 legal. A separate check of 480 fresh starts: mean 4.00 m, 86.5% legal."),
            dict(label="95th pct., older body", sub="mean of 96 fresh starts", value=F("long_jump_p95_robust96"), kind="ours",
                 tip="Starts never used in tuning: 89 of 96 legal."),
            dict(label="95th pct., calibrated body", sub="mean of 96 fresh starts", value=F("long_jump_v4_p95_robust96"), kind="ours",
                 tip="Starts never used in tuning: 77 of 96 legal (11 fell in the run, 6 somersaulted, 2 fouled)."),
            dict(label="95th pct., first jump", sub="28 Sep · one start", value=3.584, kind="ours", nd=3,
                 tip="The sprint runner's first jump with the default take-off."),
            dict(label="Elite (literature)", sub="mean of 16 perturbed starts", value=F("long_jump_elite2_robust"), kind="ours",
                 tip="One-start best 4.01 m."),
            dict(label="Average adult", sub="mean of 16 perturbed starts", value=F("long_jump_robust"), kind="ours", tip="One-start best 2.47 m."),
            dict(label="Untrained women", sub="reference", value=3.57, kind="ref", tip="3.57 ± 0.54 m (Romdhani et al. 2026)"),
            dict(label="Untrained men", sub="reference", value=4.95, kind="ref", tip="4.95 ± 0.55 m (Romdhani et al. 2026)"),
            dict(label="High-school qualifying", sub="reference", value=6.36, kind="ref",
                 tip="Boys 6.07–6.65 m (Oregon 2026 state standards). Jumpers aged 14–28 run up at 8.89 m/s (Bayraktar & Cilli 2018)."),
            dict(label="College finals", sub="reference", value=7.66, kind="ref", tip="NCAA D1 finals medians 7.56–7.75 m"),
            dict(label="World record", sub="reference", value=8.95, kind="ref", tip="Powell 1991; run-up 11.0 m/s"),
        ],
        "World Athletics rules are scored: the foul line, no somersault before landing, and the nearest mark by any body part. "
        "Bars are means over the starts named on each row; a single start is one exact starting state.")

    ch_bat = chart(
        "c-bat", "Bat speed at contact", "m/s", 40, [0, 10, 20, 30],
        [
            dict(label="Hitch-free swing", sub="27 Sep", value=13.86, kind="ours", nd=1, tip="24 pitches it never saw."),
            dict(label="Pure search (Codex)", sub="27 Sep · independent", value=14.79, kind="ours", nd=1, tip="Keeps the pause before and after contact."),
            dict(label="Contraction knots, reflexes on", sub="29 Sep · before tuning", value=19.44, kind="ours", nd=1,
                 tip="Knots distilled from the open-loop program, on the 24 newest held-out pitches: 20 of 24 hit, the four misses all low pitches."),
            dict(label="Tuned on fresh pitches", sub="29 Sep · current", value=F("bat_power_fresh_rep"), kind="ours", nd=1,
                 tip="Reflexes on. All 24 held-out pitches hit; 48 of 48 hit on 48 more untouched pitches at 26.83 m/s."),
            dict(label="Open-loop program", sub="28 Sep · reflexes off", value=25.24, kind="study", nd=1,
                 tip="An excitation program with the reflexes off. 24 of 24 hits. Built from 6 of the 18 grid pitches; the 24 fresh pitches are held out."),
            dict(label="Labelled 95th-percentile body", sub="not comparable", value=F("bat_power_fresh_rep_p95"), kind="variant", nd=1,
                 tip="The same swing on a labelled body (strength ×1.32, muscle speed ×1.2). A tuned variant reaches 32.1 on these pitches and 32.4 on 48 untouched pitches; about a fifth of its hits leave above 60°."),
            dict(label="MLB average", sub="reference", value=32.0, kind="ref", nd=1, tip="About 72 mph at the sweet spot (Savant 2024)"),
        ],
        "Athlete body (strength ×1.5, pivot root). All bars are scored on 24 fresh pitches that no swing was trained on; the two newest bars use a newer set.",
        legend_ours="Swing with reflexes on")

    ch_tt = chart(
        "c-tt", "Table tennis, phase 2", "%", 100, [0, 25, 50, 75, 100],
        [
            dict(label="First version", sub="27 Sep · all serves", value=26.7, kind="ours", nd=1, tip="Fly-by pelvis slide, sag-model height match, side switch."),
            dict(label="Backhand re-practised", sub="27 Sep · all serves", value=33.0, kind="ours", nd=1, tip="Backhand posture, swing time, reflex gain and a live-Jacobian servo."),
            dict(label="Current", sub="300 serves", value=round(tt300, 1), kind="ours", nd=1,
                 tip="A bounce-tick defect removed and the backhand re-tuned. Forehand serves 36–46%, backhand serves 23%."),
            dict(label="Current, backhand serves", sub="131 serves", value=round(100 * F("tt_p2_backhand"), 1), kind="ours", nd=1, tip="The backhand works, but weakly."),
            dict(label="Challenge winner", sub="reference", value=64, kind="ref", nd=1, tip="2025 MyoChallenge phase 2"),
            dict(label="Best reported", sub="reference, preprint", value=80.3, kind="ref", nd=1,
                 tip="Diff-Muscle (Zhao et al., arXiv 2603.08617, Mar 2026), a preprint; up to 14 dual-agent rally exchanges."),
        ],
        "MyoChallenge phase-2 success rate: the share of serves the task scores as solved.")

    charts = f'<div class="chartgrid">{ch_sprint}{ch_jump}{ch_bat}{ch_tt}</div>'

    # ------------------------------------------------------------ ability cards -----
    run_cards = [
        card("run-natural", "Natural running from human keyframes", [("7.3°", "off human running, 12 starts")],
             [vid("run_knots.mp4", out("run_knots.mp4"), "Natural runner with the literature curves ghosted",
                  "12 s of the current runner. The literature gait curves are ghosted at the current stride phase.")],
             ["Contraction keyframes at touchdown, mid-stance and toe-off from human running data, eased through and latched on the feet. The latest version adds a knot at each gait event (a contraction, a velocity and an acceleration for every muscle), fitted to the target by least squares and then improved from stride-by-stride error curves (iterative learning control).",
              "Against the human running curves from the literature it is now **7.3°** off on the 12-start trial, and against motion-capture running (Fukuchi 2017) 10.1°, falling on 11 of 48 fresh starts where the earlier runner fell on 17."],
             table(["Measured against", "Before", "Now"],
                   [["Literature curves, 12 starts", "#9.13° · 1 fall", "#7.29° · 1 fall"],
                    ["Motion capture, 48 starts", "#11.0° · 17 falls", "#10.09° · 11 falls"]]),
             body="v2 anatomy, average adult."),
        card("sprint", "Sprint", [(f"{v4p95:.2f} m/s", "95th-percentile body, five gears"), (f"{v4sp:.2f} m/s", "labelled sprinter body"), (f"{v4bd:.2f} m/s", "labelled beyond-human body")],
             [vid("sprint_v4_p95_gear5.mp4", out("sprint_v4_p95_gear5.mp4"), "Five-gear sprinter on the calibrated v4 body, 95th percentile",
                  "The five-gear runner on the calibrated body, 95th percentile, from a standing start: a crouched, high-cadence start, longer strides as the speed passes 6.5, 7.0 and 7.7 m/s, and an extended-stance gear above 7.8 m/s."),
              vid("sprint_v4_sprinter.mp4", out("sprint_v4_sprinter.mp4"), "Sprinter on a labelled stronger body",
                  "A labelled stronger body (strength ×1.55, muscle speed ×1.45), not comparable with the others: the five-gear runner with its forward lean retuned and its top gear searched again. It falls on 4 of its 12 test starts; this is one that stays up, peaking at 8.4 m/s."),
              vid("sprint_v4_beyond.mp4", out("sprint_v4_beyond.mp4"), "Sprinter on a labelled beyond-human body",
                  "A labelled body that is not human (strength ×2.4, muscle speed ×2.0; invented multipliers), never comparable with the others. From a standing start it needs about 140 m (19 s) to reach 10 m/s, then holds it: this start peaks at 10.18 m/s. It falls on 3 of its 12 test starts; this is one that stays up.")],
             ["Full drive on the prime movers, with the opposing muscles scaled down as their partners fire (reciprocal inhibition), latched on each foot. One parameter set cannot both accelerate a standing body and cruise, so the runner has gears: above set speeds the whole stride is rebuilt from the next gear's values at the next flight. The 95th-percentile runner now has five and reaches **" + f"{v4p95:.2f}" + " m/s**, up from 7.45 with two.",
              f"Two what-if bodies, labelled as such and never compared with the human-profile runners. The **sprinter** (strength ×1.55, muscle speed ×1.45, tendon ×1.5, activation ×0.8, fixed from sprinter morphology data before any runner ran on it) reaches **{v4sp:.2f} m/s** ({passes('sprint_top_speed_v4_sprinter')} starts stay up). The **beyond-human** body (strength ×2.4, muscle speed ×2.0, the same tendon and activation: an invented stretch, the smallest of three round-number steps whose ideal-control ceiling is above 14.5 m/s) reaches **{v4bd:.2f} m/s**: {passes('sprint_top_speed_v4_beyond')} test starts stay up and every one of them peaks above 10.1 m/s. The other three fall, and so do 14 to 26 of each 80 unseen standing starts. From a standing start it takes about 140 m (19 s) to reach 10 m/s and passes the 44 m mark at 7.7 m/s; at 10 m/s its stride is 4.4 steps a second of 2.3 m.",
              "The body model was calibrated against published data along the way (the calibrated body: quadriceps series stiffness and hip speeds), which is why the same runner design scores higher on it than on the older body."],
             table(["Body", "Older body", "Calibrated body"],
                   [["Average adult", f"#{V('sprint_top_speed')}", f"#{v4avg:.2f}"],
                    ["95th percentile", f"#{V('sprint_top_speed_p95')}", f"#{v4p95:.2f}"],
                    ["Elite, literature", f"#{V('sprint_top_speed_elite2')}", f"#{v4e2:.2f}"]]),
             body="Average, 95th-percentile and literature-elite bodies on the calibrated anatomy (the older anatomy for the earlier runners), plus two labelled stronger bodies (sprinter and beyond-human).",
             chips=[chip("labelled", "Includes labelled stronger bodies")]),
        card("blocks", "Sprint from blocks, keyframed on Usain Bolt", [(f"{V('sprint_blocks_30', 2)} s", "30 m from the blocks"), (f"{V('sprint_blocks_100', 1)} s", "100 m")],
             [vid("sprint_blocks.mp4", out("sprint_blocks.mp4"), "Start from blocks with Bolt's pose ghosted",
                  "Bolt's pose is ghosted over the runner. No broadcast frames are shown.")],
             ["Keyframes measured from side-view footage of Bolt at block exit, the first steps and the max-velocity cycle. The set position is the mean of the 2018 World Indoor 60 m finalists, and steps 3 to 10 are interpolated. The runner sets on two angled pads, pushes off the rear pad on its force, then the front pad, then accelerates through steps blended from Bolt's first steps into his max-velocity cycle. Reaction time is 0.237 s.",
              f"On the 95th-percentile body it covers 30 m in **{V('sprint_blocks_30')} s** and 100 m in **{V('sprint_blocks_100')} s** on 11 of 12 starts. Bolt ran 3.78 s and 9.58 s: the runner takes 3.3 steps a second of 1.7 m against his 4.5 of 2.4 to 2.7 m."],
             None,
             body="95th-percentile body only: the average body cannot leave the blocks."),
        card("touch", "Touch-only sprint", [("10 of 12", "starts stay up in the fast-running trial")],
             [vid("sprint_touch.mp4", out("sprint_touch.mp4"), "Sprint from a single touchdown keyframe", "Muscles are tinted by activation.")],
             ["Keyframing only the toe-touch: one right-touchdown keyframe (the left is its mirror), each stride one spline from touch to touch, with the joint velocities at the touch, and full-power bursts timed on each leg's own touchdown and toe-off. Without the velocities every version fell within two steps.",
              "In the fast-running trial (a naturalness score at 5 m/s) 10 of 12 starts stay up where the previous runner failed all 12. The quadriceps pulse at landing alone is worth 0.7 m/s. It runs 4.6 m/s on the average body against 5.0 for the tuned sprinter."],
             None,
             body="v3 anatomy, average adult."),
    ]

    def lj_caption(metrics_path, lead):
        try:
            m = json.load(open(os.path.join(ROOT, "out", metrics_path)))
            by = {"l_foot": "the left foot", "r_foot": "the right foot", "l_hand": "the left hand", "r_hand": "the right hand"}.get(m.get("nearest_mark_by"), "another part of the body")
            tail = " The jumper falls over after landing." if m.get("flipped") or m.get("fell_back") else ""
            return f"{lead} {m['official_m']:.3f} m; the nearest mark is by {by}.{tail} Take-off, flight and landing play at quarter speed."
        except (OSError, KeyError, ValueError):
            return lead
    lj_videos = [
        vid("long_jump_v8_v4p95.mp4", out("long_jump_v8_v4p95.mp4"), "Long jump, best mark, calibrated body",
            lj_caption("long_jump_v8_v4p95_metrics.json", "The best mark, on the calibrated body with the two-gear runner (one start, tuned to it):")),
        vid("long_jump_v7_p95.mp4", out("long_jump_v7_p95.mp4"), "Long jump on the older 95th-percentile body",
            lj_caption("long_jump_v7_p95_metrics.json", "The previous best, on the older 95th-percentile body (one start, tuned to it):")),
        vid("long_jump_v7_p95_robust.mp4", out("long_jump_v7_p95_robust.mp4"), "Long jump, robust programs, start 401",
            lj_caption("long_jump_v7_p95_robust_metrics.json", "The robust programs on one of their 16 perturbed starts (seed 401):")),
        vid("long_jump_v5_v4p95.mp4", out("long_jump_v5_v4p95.mp4"), "First long jump on the calibrated v4 body",
            lj_caption("long_jump_v5_v4p95_metrics.json", "The first jump on the calibrated body (one start):")),
    ]
    jump_cards = [
        card("longjump", "Long jump",
             [(f"{V('long_jump_v4_p95', 3)} m", "calibrated body, tuned to one start"), (f"{V('long_jump_p95_robust')} m", "older body, mean of 16 starts"),
              (f"{V('long_jump_v4_p95_robust32')} m", "calibrated body, mean of 32 fresh starts")],
             lj_videos,
             ["The run-up is the sprint runner itself. World Athletics rules are in the score: a foul line on every tick of the stance, no somersault past 120° until landing is over, no touching the runway after landing, and the mark is the nearest break in the sand by any body part. The take-off comes from an ideal-control analysis of the runner's own approach, distilled into contraction knots latched on the plant touchdown; the landing is a table of muscle excitations locked to the predicted landing time. Both are near open loop.",
              f"The best mark is **{V('long_jump_v4_p95', 3)} m** on one start, with programs tuned to that start: a best case, not a typical jump. Over starts no tuning ever used, the calibrated-body programs average {V('long_jump_v4_p95_robust32')} m over 32 (31 legal) and {V('long_jump_v4_p95_robust96')} m over 96 (77 legal); in a separate check of 480 fresh starts the mean was 4.00 m with 86.5% legal. On the older 95th-percentile body the one-start best is {V('long_jump_p95', 3)} m, the mean over 16 perturbed starts **{V('long_jump_p95_robust')} m** and over 96 fresh starts {V('long_jump_p95_robust96')} m (89 legal).",
              "For scale: untrained men jump 4.95 m on average and high-school state qualifiers 6.07–6.65 m. The best mark is 105% of the untrained-man mean; the fresh-start means are 75 to 92% of it."],
             steps([("28 Sep", "3.58 m", "first jump of the sprint runner (7.0 m/s), one start"),
                    ("28 Sep", "4.90 m", "take-off from an ideal-control analysis of the runner's own approach"),
                    ("29 Sep", "5.12 m", "a landing program learned for that start"),
                    ("29 Sep", "4.63 → 5.21 m", "calibrated body: first jump 4.63 m, then 5.21 m with the two-gear runner"),
                    ("28–29 Sep", "2.13 → 4.63 m", "mean of 16 perturbed starts: the take-off launched from the penultimate touchdown, a landing program learned on 32 hand-overs")]),
             body="v3 anatomy, 95th percentile; the calibrated v4 anatomy for the newest jump.",
             chips=[chip("tuned")]),
        card("standing", "Standing broad jump", [(f"{V('search_jump_legal', 3)} m", "legal jump, 8 starts"), (f"{V('search_jump_robust_legal', 3)} m", "32 larger nudges, all legal")],
             [vid("codex_standing_jump.mp4", CODEX + "competitor_jump_round2__video_search_jump_legal_tcn.mp4", "Standing jump, 1.363 m",
                  "The best legal jump, 1.363 m (Codex, round 2): it lands and stays on its feet."),
              vid("codex_jump_robust_r7.mp4", CODEX_ROOT + "out/competitor_jump_round7/video_search_jump_robust_legal_tcn.mp4", "Robust standing jump, 1.34 m",
                  "The best over 32 larger nudges (Codex, round 7): 1.341 m on seed 3024, legal through 20 s.")],
             [f"Contraction keyframes with take-off and landing latched on the centre of mass. The best legal jump is Codex's temporal recovery policy at **{V('search_jump_legal', 3)} m** (8 starts): a small learned correction after landing keeps the jumper on its feet. Over the 32 larger nudges the best is Codex's round-7 policy at **{V('search_jump_robust_legal', 3)} m**, {passes('search_jump_robust_legal')} landing legally at 3 s.",
              "On fresh starts checked at 8 s the round-7 policy is legal on 57 of 64; the earlier keyframe policy (1.315 m) was legal at 3 s on 64 of 64 but at 8 s on 0 of 64."],
             None,
             body="Planar v3 body.",
             chips=[chip("ext")], gallery=True),
        card("hurdles", "Hurdles", [("0.762 m", "first hurdle cleared on 4 of 8 starts"), ("0.45 m", "four hurdles in a row cleared")],
             [vid("hurdle_hs_076.mp4", out("hurdle_hs_076.mp4"), "Hurdler at 0.762 m",
                  "The best at 0.762 m (2 ft 6 in): over the first hurdle, then down before the second."),
              vid("hurdle_hs.mp4", out("hurdle_hs.mp4"), "Hurdler at high-school height, 0.991 m",
                  "High-school height, 0.991 m: the lead leg clears, the trail leg catches the bar, and the hurdler ends up flat on the track."),
              vid("hurdle_hs_attempt_34.mp4", out("hurdle_hs_attempt_34.mp4"), "Ten hurdles at 0.762 m, the first knocked",
                  "Ten hurdles at 0.762 m: the first one gets knocked over, and the hurdler keeps running."),
              vid("hurdle_hs_attempt.mp4", out("hurdle_hs_attempt.mp4"), "First try at 0.762 m",
                  "The first try at 0.762 m: one hurdle cleared cleanly, then the hurdler crumples on the landing."),
              vid("hurdle.mp4", out("hurdle.mp4"), "Four hurdles at 0.45 m, all cleared",
                  "Where it started: four 0.45 m hurdles, 9.14 m apart, all cleared.")],
             ["The lead knee is driven up and extended over the bar, and the trail leg is lifted out to the side and turned so the knee comes around. It began with four 0.45 m hurdles, all cleared. At 0.762 m it clears the first hurdle on 4 of 8 starts and then falls before the second; at high-school height, 0.991 m, the lead leg clears and the trail leg catches the bar.",
              "It reaches the first hurdle at about 4 m/s; a high-school hurdler arrives near 7."],
             None,
             body="v3 body with 3D hips (hip abduction and rotation freed).",
             gallery=True),
    ]

    ball_cards = [
        card("bat", "Baseball swing", [(f"{V('bat_power_fresh_rep', 1)} m/s", "24 held-out pitches, all hit"), (f"{V('bat_power_fresh_rep_p95', 1)} m/s", "labelled 95th-percentile body")],
             [vid("bat_r2_s10.mp4", out("bat_r2_s10.mp4"), "Swing with contraction knots, reflexes on, tuned on fresh pitches",
                  f"The current swing, in robolab's representation (contraction knots, reflexes on), tuned on fresh pitches: {V('bat_power_fresh_rep', 1)} m/s on 24 held-out pitches, all hit."),
              vid("bat_v6.mp4", out("bat_v6.mp4"), "Open-loop swing",
                  "An open-loop excitation program with the reflexes off, 25.2 m/s: the swing the current one was distilled from.")],
             ["The fast swing turns the pelvis at full drive into its yaw limit, keeps the spine coiled, fires short arm bursts with no co-contraction, and whips the bottom wrist through 0.8 rad in the last 60 ms. The earlier hitch-free swing was slow because of its plan: the arms and wrists fired at full power only 2 to 8% of the swing.",
              f"The current swing hits **{V('bat_power_fresh_rep', 1)} m/s** at contact on 24 held-out pitches (all hit, none stalling) and 26.83 on 48 more untouched pitches (48 of 48 hit). It is contraction knots with the reflexes on, tuned by sep-CMA on fresh training pitches; an aim correction alone turned 36 of 48 hits into 48 of 48. MLB hitters average about 32 m/s.",
              f"The same swing on a labelled 95th-percentile body (strength ×1.32, muscle speed ×1.2) reaches {V('bat_power_fresh_rep_p95', 1)} m/s here and up to 32.4 m/s on 48 untouched pitches with a tuned variant, at the price of ball quality: about a fifth of its hits leave above 60°."],
             steps([("27 Sep", "12.9 m/s", "hitch-free swing with a follow-through"),
                    ("27 Sep", "13.8 m/s", "a load swing: lift, plant and stride load, contact as a quintic knot"),
                    ("27 Sep", "14.7 m/s", "a pure search from a second team (Codex)"),
                    ("28 Sep", "25.2 m/s", "an open-loop program with the pelvis and upper body driven to their limits, reflexes off"),
                    ("29 Sep", "26.7 m/s", "the same swing as contraction knots with the reflexes on, tuned on fresh pitches")],
                   head=("When", "18 test pitches", "What changed")),
             body="Athlete body: strength ×1.5, every muscle's peak speed 3.0 L0/s, a pivot root with a yaw hinge and a slide, no whole-body balance. On the human-calibrated body at strength 1.0 the best swing found is 10.3 m/s.",
             chips=[chip("athlete")]),
        card("dribble", "Dribbling", [(f"{V('dribble_crossover_25', 2)}", "crossovers in 15 s"), (f"{streak_max}", f"passes through the legs in a row (mean best streak {V('dribble_btl_streak_25', 2)})"),
                                      (f"{V('dribble', 0)}", "bounces in 15 s, first dribble")],
             [vid("dribble_btl_oracle.mp4", out("dribble_btl_oracle.mp4"), "Four passes through the legs in a row",
                  f"Through the legs, on start 715 (a streak of {streak_max}), with a slow-motion replay of a pass."),
              vid("codex_crossover.mp4", CODEX_ROOT + "out/competitor_dribble_round9/video_dribble_crossover_25_tcn.mp4", "Crossover dribble",
                  f"Crossovers: Codex's round-9 policy, {V('dribble_crossover_25', 2)} per 15 s run. The ball is still lost eventually on every run."),
              vid("dribble.mp4", out("dribble.mp4"), "The first dribble, right hand",
                  f"Where it started: a right-hand dribble, {V('dribble', 0)} bounces in 15 s.")],
             [f"**Through the legs.** A stance planner picks a staggered lunge with the trunk twisted toward the lead leg, and catch spots that both hands can reach from behind the ball. The launch, the left hand's return and the right hand's return are open-loop tables of the 16 arm muscles with the reflex layer off during each stroke, gain-scheduled on the ball's predicted crossing and the stroking arm's posture; the reflex controller drives everything else. The mean longest streak is **{V('dribble_btl_streak_25', 2)}** passes in 15 s over 25 starts (it was 1.28), with at most {streak_max}; on 32 fresh starts it is {V('dribble_btl_streak_fresh32', 2)} (was 1.22), and on 64 more that nothing was tuned on 1.95, with 14 streaks of 3 or more (the reflex controller never gets past 2).",
              "**Crossovers.** A small learned correction from the recent ball motion (Codex) took the count from 3.72 to 7.52 per 15 s run, and its round-9 version, with sustained catching, to **" + V('dribble_crossover_25', 2) + "**. The trunk still pumps and the hands are rigid paddles."],
             table(["Trial", "Now", "Before"],
                   [["Crossovers per 15 s run, 25 starts", f"#{V('dribble_crossover_25')}", "#7.52 (3.72 earlier)"],
                    ["Through the legs, mean longest streak, 25 starts", f"#{V('dribble_btl_streak_25', 2)}", "#1.28"],
                    ["Through the legs, mean longest streak, 32 fresh starts", f"#{V('dribble_btl_streak_fresh32', 2)}", "#1.22"]]),
             body="Stationary pivot bodies. Through the legs: the v3 body. Crossovers: the v1 body with rigid paddle hands.",
             chips=[chip("tuned", "Through the legs: tuned tables"), chip("ext", "Crossovers: policy from Codex")]),
        card("tt", "Table tennis", [(f"{tt300:.0f}%", "phase 2, 300 serves"), ("100%", "phase 1")],
             [vid("myo_tt_r5.mp4", out("myo_tt_r5.mp4"), "Five solved serves in a row",
                  f"Five solved serves in a row (seeds 98045 to 98049) by an earlier version. The current one solves {tt300:.0f}% of serves, so this is a chosen streak, not a rally."),
              vid("myo_tt_strokes.mp4", out("myo_tt_strokes.mp4"), "Chop, wrist flick and low scoop",
                  "Chop, backhand flick and low forehand scoop with real ball spin, at the best angles found.")],
             [f"Predicts the ball through the bounce, slides the pelvis onto its path, latches the ready posture on time-to-paddle and sets the paddle face from an aim law. Phase 1 is 100%. Phase 2 is **{tt300:.0f}%** over 300 serves (26.7% then 33% on 27 Sep; {100 * F('tt_p2'):.0f}% on the earlier 100-serve set); the 2025 challenge winner scored 64%.",
              "The latest gain came from one defect. On the single tick when the table-contact flag is set the ball's velocity is mid-reversal, and the skill predicted where the ball crosses the paddle plane from it, so for that tick the plan was 0.3 to 1.6 m off on every serve; fixing it alone lifts the hit rate from 0.80 to 0.87. A re-tuned backhand took its share on fresh serves from 21.8% to 35.9%.",
              "Strokes measured with real ball spin: the best chop is the backhand at a 60° face and a 40° downward path (4 cm over the net, 11 rev/s of backspin, 3 of 11 landed); the wrist flick makes topspin under 5 rev/s."],
             None,
             body="The official MyoSuite table-tennis body: 273 muscles and 2 pelvis actuators."),
    ]

    soccer_cards = [
        card("balance", "One-leg balance", [(f"{bal_off} of {bal_off_n}", "hold five minutes, official trial"), ("37 of 37", "more fresh starts hold five minutes")],
             [vid("soccer_balance_300.mp4", out("soccer_balance_300.mp4"), "Standing on one leg for the first 40 seconds of a 298 second hold",
                  "The first 40 s of a 298 s one-leg stance on the 290-muscle body (an earlier version of the hold).")],
             [f"The hold is steered by the sensed centre of pressure, with a slow centring loop and per-posture muscle moment arms; the lift into single support was tuned on an 8 s proxy. On the 40-start trial (310 s episodes) **{bal_off} of {bal_off_n}** fresh stances stay on one leg for at least 300 s in the official, unmodified environment; the previous hold managed 34 of 40 and the one before it 24. On 37 more fresh starts it holds 37 of 37.",
              "Most of the earlier misses were a MuJoCo bug rather than balance. When a muscle line grazes its wrap cylinder, the tendon-wrap code takes the arccosine of a value that rounds just above 1 and the muscle length becomes NaN (it reproduces on MuJoCo 3.2.7 to 3.14.0), and the swing leg's rectus femoris hovered at exactly that grazing point. The new hold parks the swing knee at an angle where none of that leg's 68 wrap segments comes near its tangent, so the official environment never meets the bug: no NaN in about 27,000 start-seconds."],
             table(["Entry on the 40-start trial", "Holds 300 s, official", "Holds 300 s, guarded"],
                   [["Earlier hold", "#24 of 40", "–"],
                    ["Lift into single support tuned", "#34 of 40", "#35 of 40"],
                    ["Lift + shorter set ramp", "#38 of 40", "#39 of 40"],
                    ["Lift + shift brake", "#35 of 40", "#40 of 40"],
                    ["Lift + shift brake + parked swing knee", "#40 of 40", "not needed"]]),
             body="The official MyoSuite soccer body, 290 muscles."),
        card("soccer", "Penalty kick", [("100%", "phase 1, 50 starts"), ("0 of 100", "phase 2")],
             [vid("myo_soccer.mp4", out("myo_soccer.mp4"), "Penalty kick, phase 1", "Phase 1: 100% of 50 starts."),
              vid("soccer_p2_v4.mp4", out("soccer_p2_v4.mp4"), "Phase 2 attempt", "Phase 2 attempt: one step, then a fall.")],
             ["Shift weight, step, plant beside the ball, swing with a hip-flexor burst and knee snap latched on ball contact, aiming away from the keeper. Phase 1 scores every time. Phase 2 starts 0.02 to 1.4 m from that stance and lasts 10 s, and it scores 0 of 100 (the 2025 winner scored 32%).",
              "The phase-1 kick is a knife-edge trajectory from one exact start. On 48 held-out starts it scores 46 with no joint noise, 18 with ±0.001 rad, 14 with ±0.002 rad and 0 with ±0.01 rad, while the official reset draws ±0.02 rad on every joint."],
             None,
             body="The official MyoSuite soccer body, 290 muscles."),
    ]

    myo_cards = [
        small("relocate", "Relocate", vid("relocate_v6.mp4", out("relocate_v6.mp4"), "Relocate, round 6", "A 295 g object from the far left, carried and held inside the box."),
              f"Official score {V('relocate_p2eval_official', 3)} on the evaluation environment (was 0.210), genuine lifts {V('relocate_p2eval_lift', 3)}; on the easier phase-2 environment, lifts {V('relocate_p2_300', 3)}. MyoSuite 2.12.2 steps a second copy of the scene whose receptacle sits at the random target, invisible to the observation, while the visible box has no walls; reported upstream as MyoHub/myosuite issue 416. Scores here are not comparable to the 2023 winner's 0.343."),
        small("chase", "Chase tag", vid("myo_chase_v2.mp4", out("myo_chase_v2.mp4"), "Chase tag", "Two leg tracks with turning."),
              f"Phase 1 {V('chase_p1', 3)}; phase 2 {V('chase_p2', 2)} against the 2023 winner's 0.666 on the final evaluation. Each leg loops stance, push, lift and reach on its own sensed events; a step-turn loop turns toward an opponent behind."),
        small("walk", "Walking on the myoLeg", vid("myo_walk_v2.mp4", out("myo_walk_v2.mp4"), "MyoLeg walking with the longer stride", "The 80-muscle leg model with the longer stride: 0.46 m steps at 1.44 m/s, until it reaches the arena edge."),
              f"Step length {V('walk_stride', 2)} m (it was 0.36; people take about 0.7), at about 1.45 m/s at any commanded speed. Quiet standing survives 2 to 4 of 4 pushes of 60 to 80 N, not 100 N."),
        small("baoding", "Baoding balls", vid("myo_baoding_v3.mp4", out("myo_baoding_v3.mp4"), "Baoding balls", "Palm tilt and roll tied to the ball angle."),
              f"Score {V('baoding_p2', 3)} against the 2022 winner's 0.55. It holds both balls and nudges them but has not found a rolling gait."),
        small("die", "Die reorientation", vid("myo_die_v3.mp4", out("myo_die_v3.mp4"), "Die", "Finger flips plus palm tilt and roll."),
              f"No full solves (0 of 100) against the co-winners' 0.13. It removes {V('die_p2_progress', 2)} rad of the die's rotation (it was 0.19)."),
        small("bimanual", "Bimanual handover", vid("bimanual_v4.mp4", out("bimanual_v4.mp4"), "Bimanual handover", "The arm holds the box out steadily."),
              f"Staged progress {V('bimanual_stages', 2)} (it was 0.33), no full success. The prosthesis mostly presses its hand against the held box; it is not yet a grip."),
    ]

    # ------------------------------------------------------------ notes --------------
    notes = (
        '<ul class="list">'
        '<li><strong>Starts.</strong> A result is a mean over a fixed set of starting states (perturbed poses and ball or pitch positions). '
        'Fresh starts are ones that never took part in tuning. A single start is one exact state, and a program tuned to it is labelled as such.</li>'
        '<li><strong>Bodies.</strong> The 95th-percentile body scales published muscle data (strength ×1.32, muscle speed ×1.2, tendon stiffness ×1.5). '
        'The calibrated body adds two literature-backed changes (quadriceps series stiffness, hip speeds). The athlete body, used for the swing, has strength ×1.5. '
        'A labelled body is stronger than any of these and is never compared with them.</li>'
        '<li><strong>Codex.</strong> A second team runs its own challenger campaign; its policies appear where they hold the best result, and are marked.</li>'
        '<li><strong>Videos.</strong> Copy link copies the address of a public copy of the video on thecompanygardener.yaks.app/robolab, so it opens for anyone even though this page is private. They are renders of our simulations; no third-party footage is hosted.</li>'
        '</ul>')

    # ------------------------------------------------------------ assemble -----------
    def section(eyebrow, title, intro, *blocks):
        t = f"<h2>{e(title)}</h2>" if title else ""
        i = f"<p>{md(intro)}</p>" if intro else ""
        return f'<section><div class="eyebrow">{e(eyebrow)}</div>{t}{i}{"".join(blocks)}</section>'

    page = f'''<title>Robolab Progress</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Semi+Condensed:wght@500;600;700&family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>{CSS}</style>
<div class="wrap">
  <header class="head">
    <div class="eyebrow">Robolab · updated {UPDATED}</div>
    <h1>Robolab, ability by ability</h1>
    <p class="lede">Muscle-driven human bodies in MuJoCo, steered by contraction programs written in Tungsten. Each ability shows its best result, its newest videos and how it got there. Results are means over fixed sets of starts; where a program is tuned to one exact start, or a body is stronger than a human's, the card says so.</p>
    <div class="board" aria-label="Best result per ability">{board}</div>
  </header>

  {section("Compared with people", "How the results compare", "Solid bars are robolab's results; grey bars are people or challenge winners. Hover or focus a row for its note, or switch a chart to its table.", charts)}

  {section("Running and sprinting", "", "", "".join(run_cards))}
  {section("Jumping and hurdles", "", "", "".join(jump_cards))}
  {section("Ball skills", "", "", "".join(ball_cards))}
  {section("Balance and soccer · MyoChallenge 2025 body, 290 muscles", "", "", "".join(soccer_cards))}
  {section("MyoChallenge arm and leg tasks", "", "The same control plane on the official MyoSuite bodies and scoring.", '<div class="cols">' + "".join(myo_cards) + "</div>")}

  {section("Reading the numbers", "", "", notes)}
</div>
<div id="tip" role="tooltip" hidden></div>
<script>{JS}</script>
'''
    return page


def local_sources():
    """Published name -> source path relative to bits/tungsten-robolab; other worktrees' files are copied in."""
    import shutil
    assets = os.path.join(ROOT, "scratchpad", "abilities", "assets")
    out_map = {}
    for name, src in VIDEOS.items():
        if not os.path.isfile(src):
            continue
        if not os.path.abspath(src).startswith(ROOT + os.sep):
            os.makedirs(assets, exist_ok=True)
            dst = os.path.join(assets, name)
            if not os.path.isfile(dst) or os.path.getsize(dst) != os.path.getsize(src):
                shutil.copyfile(src, dst)
            src = dst
        out_map[name] = os.path.relpath(src, ROOT)
    return out_map


def published_names():
    try:
        return set(json.load(open(PUBLISHED)))
    except (OSError, ValueError):
        return set()


def main():
    page = build()
    path = os.path.join(HERE, "progress.html")
    open(path, "w").write(page)
    files = local_sources()
    missing = [k for k in VIDEOS if k not in files]
    total = sum(os.path.getsize(os.path.join(ROOT, v)) for v in files.values())
    print(f"wrote {path} ({len(page) / 1024:.0f} KB); {len(VIDEOS)} videos, {total / 1e6:.1f} MB", file=sys.stderr)
    for k in missing:
        print("MISSING", k, VIDEOS[k], file=sys.stderr)
    if "--files" in sys.argv:
        print(json.dumps(files, indent=0))
    if "--publish" in sys.argv:
        have = published_names()
        new = {k: v for k, v in files.items() if k not in have}
        drop = sorted(k for k in have if k not in files)
        size = sum(os.path.getsize(os.path.join(ROOT, v)) for v in new.values())
        print(f"publish: {len(new)} new videos ({size / 1e6:.1f} MB), {len(drop)} to remove", file=sys.stderr)
        print(json.dumps({**new, **{k: None for k in drop}}, indent=0))
    if "--mark-published" in sys.argv:
        json.dump(sorted(files), open(PUBLISHED, "w"), indent=0)
        print(f"recorded {len(files)} published videos in {PUBLISHED}", file=sys.stderr)


if __name__ == "__main__":
    main()
