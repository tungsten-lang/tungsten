#!/usr/bin/env python3
"""Build the robolab abilities page (progress.html) and print its file map.

    .venv/bin/python site/progress/build_progress.py            # writes site/progress/progress.html
    .venv/bin/python site/progress/build_progress.py --files    # also prints the publish file map (JSON)

The page is one HTML file plus the videos it references. Numbers in the board, the
goals table and the charts are read from playground/arena/champions.json, so they
follow the arena; the prose carries dated statements and is edited by hand here.
Design: the same tokens, type and row layout as the earlier progress page (Barlow
Semi Condensed / IBM Plex), so the page keeps looking like itself.
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
TRIALS = json.load(open(os.path.join(ROOT, "playground/arena/trials.json")))
CODEX_ROOT = "/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/"
CODEX = CODEX_ROOT + "results-page/dist/assets/"

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


def vid(name, src, label, caption=None):
    VIDEOS[name] = src
    cap = f'<figcaption>{md(caption)}</figcaption>' if caption else ""
    wh = mp4_size(src)
    ar = f' style="aspect-ratio: {wh[0]} / {wh[1]}"' if wh else ""
    return (f'<figure class="media"><video src="{e(name)}" controls muted loop playsinline preload="metadata"{ar} '
            f'aria-label="{e(label)}"></video>{cap}</figure>')


def out(name):
    return os.path.join(ROOT, "out", name)


# ---------------------------------------------------------------- chips ----------
CHIP = {
    "done": ("done", "Champion"),
    "run": ("run", "In progress"),
    "stuck": ("stuck", "Blocked"),
    "study": ("study", "Ceiling study"),
    "prov": ("prov", "Provisional"),
    "ext": ("study", "Independent (Codex)"),
    "scored": ("stuck", "Scored"),
}


def chip(kind, text=None):
    cls, default = CHIP[kind]
    return f'<span class="chip {cls}">{e(text or default)}</span>'


# ---------------------------------------------------------------- tables ---------
def table(head, rows, wide=False, ours=()):
    """rows: list of lists; a cell starting with '#' is a number cell."""
    th = "".join(f"<th>{md(h)}</th>" for h in head)
    body = []
    for i, r in enumerate(rows):
        tds = []
        for c in r:
            if isinstance(c, str) and c.startswith("#"):
                tds.append(f'<td class="n">{md(c[1:])}</td>')
            else:
                tds.append(f"<td>{md(c)}</td>")
        cls = ' class="ours"' if i in ours else ""
        body.append(f"<tr{cls}>{''.join(tds)}</tr>")
    w = " wide" if wide else ""
    return f'<div class="tablewrap"><table class="{w.strip()}"><tr>{th}</tr>{"".join(body)}</table></div>'


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


def chart(cid, title, unit, axis_max, ticks, rows, note, target=None, legend_ours="Robolab best"):
    """Bullet-style horizontal bars.

    rows: dict(label, sub, value, ceiling, kind, tip, shown) with kind in
    ours | study | ref. 'ours' = solid accent bar, optional outline track = ceiling;
    'study' = outline only (open-loop ceiling study); 'ref' = grey (people, winners).
    """
    used = {r["kind"] for r in rows} | ({"ceil"} if any(r.get("ceiling") for r in rows) else set())
    pct = lambda v: 100.0 * v / axis_max
    grid = "".join(f'<i class="cgrid" style="left:{pct(t):.2f}%"></i>' for t in ticks)
    axis = "".join(f'<span style="left:{pct(t):.2f}%">{num(t)}</span>' for t in ticks)
    tgt = tlab = ""
    if target:
        tgt = f'<i class="ctarget" style="left:{pct(target["v"]):.2f}%"></i>'
        tlab = f'<span class="ctlabel" style="left:{pct(target["v"]):.2f}%">{e(target["label"])}</span>'
    lines, trs = [], []
    for r in rows:
        v, c, k = r["value"], r.get("ceiling"), r["kind"]
        end = max(v, c or 0)
        fv = (lambda x, nd=r["nd"]: f"{x:.{nd}f}") if r.get("nd") else num
        shown = r.get("shown") or (f'<b>{fv(v)}</b> of {num(c)}' if c else f'<b>{fv(v)}</b>')
        marks = ""
        if k == "ours":
            if c:
                marks += f'<span class="ctrack" style="width:{pct(c):.2f}%"></span>'
            marks += f'<span class="cbar" style="width:{pct(v):.2f}%"></span>'
        elif k == "study":
            marks += f'<span class="ctrack study" style="width:{pct(v):.2f}%"></span>'
        else:
            marks += f'<span class="cbar ref" style="width:{pct(v):.2f}%"></span>'
        tip_v = f'{fv(v)} {unit}' + (f' (ceiling {num(c)})' if c else "")
        lines.append(
            f'<div class="crow" tabindex="0" data-l="{e(r["label"])}" data-v="{e(tip_v)}" data-n="{e(r.get("tip", ""))}">'
            f'<div class="clabel">{e(r["label"])}<small>{e(r.get("sub", ""))}</small></div>'
            f'<div class="cplot">{grid}{tgt}{marks}<span class="cval" style="left:calc({pct(end):.2f}% + 8px)">{shown}</span></div></div>')
        kind_txt = {"ours": "robolab", "study": "ceiling study", "ref": "people / winners"}[k]
        trs.append(f'<tr><td>{e(r["label"])}<br><small>{e(r.get("sub", ""))}</small></td><td class="n">{fv(v)} {e(unit)}</td>'
                   f'<td class="n">{(num(c) + " " + e(unit)) if c else "–"}</td><td>{kind_txt}</td><td>{e(r.get("tip", ""))}</td></tr>')
    legend = []
    if "ours" in used:
        legend.append(f'<span><i class="sw ours"></i>{e(legend_ours)}</span>')
    if "ceil" in used:
        legend.append('<span><i class="sw ceil"></i>Ceiling with perfect control</span>')
    if "study" in used:
        legend.append('<span><i class="sw ceil"></i>Open-loop ceiling study</span>')
    if "ref" in used:
        legend.append('<span><i class="sw ref"></i>People or challenge winners</span>')
    return f'''<figure class="chart" id="{cid}">
  <div class="chead"><h3>{e(title)}</h3><button type="button" class="tbtn" aria-pressed="false" data-target="{cid}">Table</button></div>
  <div class="legend">{"".join(legend)}</div>
  <div class="cview">
    <div class="cbody">{"".join(lines)}
      <div class="caxis"><div class="cspacer"></div><div class="cticks">{axis}{tlab}</div></div>
    </div>
  </div>
  <div class="tview" hidden><div class="tablewrap"><table class="wide"><tr><th>Row</th><th>Value</th><th>Ceiling</th><th>Kind</th><th>Note</th></tr>{"".join(trs)}</table></div></div>
  <figcaption class="note">{md(note)}</figcaption>
</figure>'''


# ---------------------------------------------------------------- cards ----------
def card(cid, title, chips, media, paras, tbl=None, nxt=None, body=None):
    ch = " ".join(chips)
    text = "".join(f"<p>{md(p)}</p>" for p in paras)
    bl = f'<p class="bodyline"><b>Body.</b> {md(body)}</p>' if body else ""
    nx = f'<p class="next"><b>Next.</b> {md(nxt)}</p>' if nxt else ""
    return f'''<article class="skill" id="{cid}">
  <div class="mediacol">{"".join(media)}</div>
  <div class="side"><h3>{e(title)}</h3><div class="chips">{ch}</div>{bl}{text}{tbl or ""}{nx}</div>
</article>'''


def small(title, chips, media, text):
    return (f'<article class="model"><h3>{e(title)}</h3><div class="chips">{" ".join(chips)}</div>{media}'
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
.wrap { max-width: 1120px; margin: 0 auto; display: grid; gap: 40px; }
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
.slot { background: var(--surface); border: 1px solid var(--rule); border-radius: 8px; padding: 12px 14px; display: grid; gap: 6px; align-content: start; color: inherit; text-decoration: none; }
a.slot:hover { border-color: var(--muted); }
a.slot:focus-visible, .crow:focus-visible, .tbtn:focus-visible, video:focus-visible { outline: 2px solid var(--info); outline-offset: 2px; }
.slot .name { font: 600 19px/1.1 var(--display); }
.slot .num { font: 500 13px/1.35 var(--mono); color: var(--muted); font-variant-numeric: tabular-nums; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; }
.chip { justify-self: start; font: 600 11px/1 var(--body); letter-spacing: 0.08em; text-transform: uppercase; padding: 5px 8px; border-radius: 999px; white-space: nowrap; }
.chip.done { color: var(--ok); background: var(--ok-soft); }
.chip.run { color: var(--run); background: var(--run-soft); }
.chip.stuck { color: var(--muted); background: var(--soft); }
.chip.study { color: var(--info); background: var(--info-soft); }
.chip.prov { color: var(--muted); background: transparent; box-shadow: inset 0 0 0 1px var(--muted); }
.skill { display: grid; grid-template-columns: minmax(0, 1.3fr) minmax(0, 1fr); gap: 22px; align-items: start; padding-top: 22px; border-top: 1px solid var(--rule); scroll-margin-top: 16px; }
@media (max-width: 900px) { .skill { grid-template-columns: 1fr; } }
.mediacol { display: grid; gap: 12px; min-width: 0; }
.media { margin: 0; display: grid; gap: 6px; min-width: 0; }
.media figcaption { font-size: 12.5px; color: var(--muted); }
video { width: 100%; max-width: 100%; border-radius: 6px; background: #0b0f13; display: block; aspect-ratio: 960 / 544; }
.side { display: grid; gap: 12px; min-width: 0; }
.side p { color: var(--muted); font-size: 14px; }
.side p.next { color: var(--ink); }
.side p.bodyline { font-size: 12.5px; }
.tablewrap { overflow-x: auto; background: var(--surface); border: 1px solid var(--rule); border-radius: 8px; max-width: 100%; }
table { border-collapse: collapse; width: 100%; font-size: 13.5px; }
th, td { text-align: left; padding: 7px 10px; border-bottom: 1px solid var(--rule); vertical-align: top; }
th { font-size: 12px; color: var(--muted); font-weight: 600; letter-spacing: 0.04em; }
td small { color: var(--muted); }
td.n { font-family: var(--mono); font-variant-numeric: tabular-nums; white-space: nowrap; }
tr.ours td { color: var(--accent); font-weight: 500; }
tr:last-child td { border-bottom: 0; }
.wide { min-width: 640px; }
.side table { font-size: 13px; }
.side th, .side td { padding: 7px 8px; }
.model { background: var(--surface); border: 1px solid var(--rule); border-radius: 8px; padding: 18px; display: grid; gap: 10px; align-content: start; min-width: 0; }
.mono { font-family: var(--mono); font-size: 13px; }
.cols { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 18px; }
ul.list { margin: 0; padding-left: 20px; display: grid; gap: 6px; font-size: 14px; }
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
.sw.ceil { box-shadow: inset 0 0 0 1.5px var(--accent); }
.sw.ref { background: var(--ref); }
.cbody { position: relative; display: grid; gap: 8px; padding-top: 18px; }
.crow { display: grid; grid-template-columns: minmax(96px, 30%) 1fr; align-items: center; gap: 10px; min-height: 30px; border-radius: 6px; }
.crow:hover { background: var(--soft); }
.clabel { font-size: 13px; line-height: 1.25; }
.clabel small { display: block; color: var(--muted); font-size: 11.5px; }
.cplot { position: relative; height: 22px; margin-right: 104px; }
.cgrid { position: absolute; top: -4px; bottom: -4px; width: 0; border-left: 1px solid var(--rule); }
.cbar, .ctrack { position: absolute; left: 0; top: 50%; transform: translateY(-50%); border-radius: 0 4px 4px 0; }
.cbar { height: 12px; background: var(--accent); }
.cbar.ref { background: var(--ref); }
.ctrack { height: 20px; box-shadow: inset 0 0 0 1.5px var(--accent); border-radius: 0 5px 5px 0; }
.ctrack.study { height: 16px; }
.cval { position: absolute; top: 50%; transform: translateY(-50%); font: 500 12.5px/1 var(--mono); color: var(--muted); white-space: nowrap; background: var(--surface); padding: 2px 3px; border-radius: 3px; }
.cval b { color: var(--ink); font-weight: 600; }
.caxis { display: grid; grid-template-columns: minmax(96px, 30%) 1fr; gap: 10px; }
.cticks { position: relative; height: 34px; margin-right: 104px; font: 500 11px/1 var(--mono); color: var(--muted); }
.cticks span { position: absolute; transform: translateX(-50%); }
.ctarget { position: absolute; top: -5px; bottom: -5px; width: 0; border-left: 1.5px solid var(--ink); }
.ctlabel { position: absolute; top: 18px; transform: translateX(-50%); font: 600 11px/1 var(--body); color: var(--ink); white-space: nowrap; }
#tip { position: fixed; z-index: 20; pointer-events: none; background: var(--surface); color: var(--ink); border: 1px solid var(--rule); border-radius: 8px; padding: 9px 11px; max-width: 260px; font-size: 12.5px; box-shadow: 0 6px 22px rgba(0,0,0,.18); }
#tip b { display: block; font: 600 15px/1.2 var(--mono); }
#tip span { display: block; color: var(--muted); }
@media (max-width: 560px) { .crow, .caxis { grid-template-columns: 1fr; gap: 2px; } .caxis .cspacer { display: none; } .cplot { margin-top: 2px; } }
@media (prefers-reduced-motion: reduce) { * { scroll-behavior: auto !important; } }
"""

JS = r"""
(function () {
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
"""


def build():
    # colour check for the chart marks against both surfaces (>= 3:1 for marks)
    for name, fg, bg in (("accent/light", "#C9432C", "#FFFFFF"), ("accent/dark", "#EF6A4E", "#172029"),
                         ("ref/light", "#8794A1", "#FFFFFF"), ("ref/dark", "#6E7D8B", "#172029")):
        assert contrast(fg, bg) >= 3.0, (name, contrast(fg, bg))

    n_trials = len(TRIALS)
    n_champs = len(CHAMPS)
    streak_max = int(max(scores_ok("dribble_btl_streak_25")))
    btl_any = sum(1 for x in scores_ok("dribble_btl_streak_25") if x >= 1)
    btl_two = sum(1 for x in scores_ok("dribble_btl_streak_25") if x >= 2)
    btl_n = len(scores_ok("dribble_btl_streak_25"))
    bal40 = scores_ok("soccer_single_leg_310_40")
    bal40_hold = int(round(sum(bal40)))          # bal1_300 is 1 when the hold reaches 300 s
    bal40_n = len(CHAMPS["soccer_single_leg_310_40"].get("scores", [])) or len(bal40)
    v4p95 = V("sprint_top_speed_v4_p95") if scores_ok("sprint_top_speed_v4_p95") else None
    v4e2 = V("sprint_top_speed_v4_elite2") if scores_ok("sprint_top_speed_v4_elite2") else None
    v4p95_pct = round(100 * F("sprint_top_speed_v4_p95") / 10.45) if v4p95 else None

    # ------------------------------------------------------------ board -------------
    board_items = [
        ("run-natural", "Natural running", "done", "7.3° from human running, 12 starts"),
        ("sprint", "Sprint", "run", f"95th pct.: {V('sprint_top_speed_p95')} m/s v3" + (f" · {v4p95} v4" if v4p95 else "")),
        ("blocks", "Sprint from blocks", "done", f"30 m in {V('sprint_blocks_30')} s · Bolt 3.78"),
        ("longjump", "Long jump", "run", f"{V('long_jump_p95', 2)} m best (one start) · {V('long_jump_p95_robust')} m robust"),
        ("standing", "Standing jump", "done", f"{V('search_jump_legal', 3)} m legal · {V('search_jump_robust_legal', 3)} robust"),
        ("hurdles", "Hurdles", "stuck", "0.762 m: 4 of 8 clear hurdle 1"),
        ("bat", "Baseball swing", "run", f"{V('bat_power_fresh_rep', 1)} m/s, reflexes on, athlete body"),
        ("dribble", "Dribble", "run", f"through the legs: mean streak {V('dribble_btl_streak_25', 2)}, max {streak_max}"),
        ("tt", "Table tennis", "stuck", f"P2 {100 * F('tt_p2_300'):.0f}% · P1 100%"),
        ("balance", "One-leg balance", "run", f"{bal40_hold} of {bal40_n} hold 5 minutes"),
        ("soccer", "Penalty kick", "stuck", "P1 100% · P2 0%"),
        ("relocate", "Relocate", "scored", f"{V('relocate_p2eval_official', 3)} on the eval env"),
        ("chase", "Chase tag", "scored", f"P1 {V('chase_p1', 2)} · P2 {V('chase_p2', 2)} (winner 0.666)"),
        ("walk", "Walking", "scored", f"{V('walk_stride', 2)} m steps at 1.45 m/s"),
        ("baoding", "Baoding balls", "scored", f"{V('baoding_p2', 3)} (winner 0.55)"),
        ("die", "Die and bimanual", "stuck", "no full solves yet"),
    ]
    board = "".join(
        f'<a class="slot" href="#{i}"><span class="name">{e(n)}</span>{chip(k)}<span class="num">{e(t)}</span></a>'
        for i, n, k, t in board_items)

    # ------------------------------------------------------------ goals -------------
    goals = table(
        ["Goal", "Best now", "Compared with", "What stands in the way"],
        [
            ["Increase the bat speed",
             f"{V('bat_power_fresh_rep', 1)} m/s on 24 held-out pitches with reflexes on, all 24 hit and all passing the hitch guard (was 13.9), on the athlete body; 26.37 on 48 other fresh pitches. The open-loop ceiling study scored 25.2 on an earlier set of 24.",
             "MLB average about 32 m/s",
             "The trunk and the elbows are far from their speed limits and range ends: torque times time over inertia, and the chain's own sequencing, limit them (the pelvis peaks 119 ms before contact and brakes). MLB swings are about 32 m/s."],
            ["Dribble through the legs",
             f"Arena, 25 starts: mean longest streak {V('dribble_btl_streak_25', 2)} in 15 s, at most {streak_max}; at least one good pass on {btl_any} of {btl_n}. The video shows a streak of 3 on a start found by scanning seeds.",
             "Target: several in a row",
             "The receiving hand cannot take a fast, flat ball and relaunch it high; the arms lag the plan."],
            ["Exceed 10 m/s in the sprint",
             f"95th-percentile body: {V('sprint_top_speed_p95')} m/s on v3 and " + (f"{v4p95} m/s on the calibrated v4 body ({passes('sprint_top_speed_v4_p95')} starts)" if v4p95 else "no v4 runner yet") + f". Elite (literature) v4: {v4e2 or '–'}; average v4: {V('sprint_top_speed_v4')}.",
             "Ceiling with perfect control on v4: 10.45 (95th pct.). Recreationally active adults 7.8, trained sprinters 9.9.",
             (f"The v4 95th-percentile runner is at {v4p95_pct}% of its ceiling; 10 m/s needs 96%. It runs in four gears (a crouched start, then rebuilt strides above 6.5, 7.0 and 7.7 m/s); the gain per gear shrank (+0.45, +0.41, +0.05 m/s), so this crouched family saturates near 8 m/s, and the extended stance the ideal needs falls on 60% of standing starts." if v4p95 else "10 m/s on v4 needs 96% of the 95th-percentile ceiling.")],
            ["Long jump with the best runner, then beyond human",
             f"One start: {V('long_jump_p95', 2)} m on the 95th-percentile body (oracle-class landing, overfit to that start; 103% of the untrained-man mean). 16 perturbed starts: {V('long_jump_p95_robust')} m; 96 fresh starts: {V('long_jump_p95_robust96')} m (89 of 96 legal). Near-open-loop take-off and landing programs (oracle-class). v4 jump with the two-gear runner: {V('long_jump_v4_p95', 3)} m on one start, not robust yet (2.85 m on 32 fresh starts, 25 legal).",
             "Untrained men 4.95 m, high-school qualifiers 6.07–6.65 m, world record 8.95 m",
             f"Speed is what is missing: by the agent's fit, 5.5 m robustly needs 7.3 m/s at the board and 6.07 m needs 8.2–9.0 m/s. The v4 95th-percentile runner now peaks at {v4p95 or 'about 7'} m/s (7.0 when the v4 jump was built), and a long-jump agent is putting it under the jump. About 2% of fresh starts somersault and 2% stumble in the run-up."],
            ["Table tennis phase 2 above 90%",
             f"{100 * F('tt_p2_300'):.0f}% over 300 serves ({100 * F('tt_p2'):.0f}% over 100)",
             "Winner 64% (2025); 80.3% in a Mar 2026 preprint",
             "At the arm's measured execution noise (face 10°, pad velocity 0.5 m/s, place 5 cm) even a perfect plan tops out near 45%; 90% needs about 4°, 0.25 m/s and 3 cm at once, three to four times quieter. The forehand is stuck near 38–40%."],
            ["Balance five minutes on one leg",
             f"{bal40_hold} of {bal40_n} fresh stances hold at least 300 s on the 40-start strict trial (the previous champion held 24 of 40). On the older 20-start trial the champion holds 12 of 20. The routine also holds the right leg first (8 of 8 starts).",
             "Target: 300 s",
             "Six of 40 still fall in the official trial: five early failures (in the lift, the shift or the hold after it) and one MuJoCo blow-up. The blow-ups are a MuJoCo bug (seen in 3.2.7 to 3.14.0, and upstream main has the same code): the tendon-wrap code takes the arccosine of a value that rounds just above 1 when a muscle line grazes its wrap cylinder, and the muscle length becomes NaN. With a labelled guard that nudges the state by under 1e-10 rad when it happens, the shift-brake variant holds 40 of 40 stances for five minutes (p 0.034 over the guarded lift champion), 68 of 69 more fresh stances, and 118 of 120 for 20 s."],
            ["Score all the soccer goals",
             "Phase 1 100%. Phase 2 0 of 100.",
             "2025 winner 32% on phase 2",
             "A closed-loop kick was built and tested (agent P): it does not close even 0.002 rad of joint noise (14 of 48 held-out starts score, from 46 of 48 with none), while the official reset draws 0.02 rad on every joint (0 of 48). The kick needs the stance to about 2 cm sideways and a 1.3–2.6 kN thigh-against-shank contact, and only 6 of the 100 starts are within 0.3 m of the stance. The approach needs a walking gait this body has not shown: its spine folds."],
            ["Improve robolab",
             f"{n_trials} arena trials ({n_champs} with a champion), a calibrated v4 body, a MyoSuite relocate bug found, two compiler fixes merged into main.",
             "–",
             "See what is running, near the end."],
        ], wide=True)

    # ------------------------------------------------------------ charts ------------
    sprint_rows = []
    if v4p95:
        sprint_rows.append(dict(label="95th pct., v4 body", sub="calibrated body", value=F("sprint_top_speed_v4_p95"), ceiling=10.45, kind="ours",
                                tip="Ceiling with perfect control and a free torso on v4: 10.45. Four gears: a crouched start, then rebuilt strides above 6.5, 7.0 and 7.7 m/s. Falls on 40 unseen starts: 2 and 1 (two seed sets)."))
    if v4e2:
        sprint_rows.append(dict(label="Elite (literature), v4", sub="calibrated body", value=F("sprint_top_speed_v4_elite2"), ceiling=9.28, kind="ours",
                                tip="Ceiling on v4: 9.28. Three gears. One of the 12 arena starts falls (seed 231, at 8.6 s); 1 and 2 of 40 unseen starts fall."))
    sprint_rows.append(dict(label="Average, v4 body", sub="calibrated body", value=F("sprint_top_speed_v4"), ceiling=8.2, kind="ours",
                            tip="Ceiling on v4: 8.2. Three gears, on a bent-knee gait found from the 95th-percentile search (it replaced a straight-leg 4.65 m/s gait). Falls on 40 unseen starts: 0 and 5 (four of them at 5-7 s)."))
    sprint_rows += [
        dict(label="95th pct., v3 body", sub="older body", value=F("sprint_top_speed_p95"), ceiling=9.69, kind="ours",
             tip="Ceiling with perfect control and a free torso on the v3 body: 9.69."),
        dict(label="Elite (literature), v3 body", sub="older body", value=F("sprint_top_speed_elite2"), ceiling=8.5, kind="ours",
             tip="Ceiling on v3: 8.5. Every part of this profile is cited; its knee and ankle extensors sit near the untrained mean."),
        dict(label="Average, v3 body", sub="older body", value=F("sprint_top_speed"), ceiling=6.89, kind="ours", tip="Ceiling on v3: 6.89."),
        dict(label="Recreationally active adults", sub="reference", value=7.8, kind="ref",
             tip="7.3–8.3 m/s: Lazarczuk et al. 2025 (7.77 ± 0.86, mixed group) and Clark, Meng & Stearne 2020 (8.23)"),
        dict(label="Trained sprinters", sub="reference", value=9.9, kind="ref", tip="9.90 ± 0.46 m/s, 79 sprinters (Miyashiro et al. 2019)"),
        dict(label="Usain Bolt", sub="reference", value=12.34, kind="ref",
             tip="12.34 m/s over 60–80 m of his 9.58 s run (Mackala & Mero 2013). Elite sprinters run 11.5–12.3 m/s."),
    ]
    ch_sprint = chart(
        "c-sprint", "Sprint speed", "m/s", 15, [0, 3, 6, 9, 12], sprint_rows,
        "Bars are arena champions; each outline is the ideal-control ceiling with the torso free on the same body. An earlier 10.2 m/s ceiling rested on an ideal torso stabiliser and is not used.",
        target=dict(v=10, label="Goal 10 m/s"))

    ch_jump = chart(
        "c-jump", "Long jump", "m", 10, [0, 2, 4, 6, 8, 10],
        [
            dict(label="Average body", sub="16 perturbed starts", value=F("long_jump_robust"), kind="ours", tip="One-start best 2.47 m."),
            dict(label="95th pct., 16 starts", sub="7.02 m/s runner", value=F("long_jump_p95_robust"), ceiling=4.93, kind="ours",
                 tip="Near-open-loop take-off and landing programs (oracle-class). On 96 fresh starts never used in practice: mean 4.23 m, 87 legal."),
            dict(label="95th pct., one start", sub="7.02 m/s runner", value=F("long_jump_p95"), ceiling=4.93, kind="ours", nd=3,
                 tip="The start its take-off and landing were designed from (ideal take-off 4.93 m; the landing reaches forward, so the mark can pass it). Oracle-class, overfit to this start."),
            dict(label="95th pct., 96 fresh starts", sub="7.02 m/s runner", value=F("long_jump_p95_robust96"), ceiling=4.93, kind="ours",
                 tip="Starts no search or practice ever used: 89 of 96 legal. A separate check of 384 fresh starts: 95.8% legal, 2.3% somersaults, mean 4.48 m."),
            dict(label="95th pct., v4 body, one start", sub="two-gear runner", value=F("long_jump_v4_p95"), ceiling=5.219, kind="ours", nd=3,
                 tip="Ideal take-off from the two-gear runner's own penultimate-touchdown state (6.59 m/s): 5.219 m ballistic from the foot, still improving when the search stopped. Oracle-class open loop, one start. Not robust yet: the robust programs, built for the earlier runner, score 2.54 m on 96 fresh starts, a third failing."),
            dict(label="95th pct., v4 body, 32 fresh starts", sub="two-gear runner", value=F("long_jump_v4_p95_robust32"), kind="ours", nd=2,
                 tip="Two-gear runner, hip-nudge run-up steering, an upright final approach, a take-off program fitted over 32 approaches of both plant sides and a landing program learned on 62 hand-overs (all near open loop, oracle-class). Starts never used in practice; the earlier programs scored 2.85 m."),
            dict(label="95th pct., v4 body, 96 fresh starts", sub="two-gear runner", value=F("long_jump_v4_p95_robust96"), kind="ours", nd=2,
                 tip="The same programs on 96 fresh starts; the earlier programs scored 2.54 m, a third of the starts failing."),
            dict(label="Elite, literature", sub="16 perturbed starts", value=F("long_jump_elite2_robust"), ceiling=4.25, kind="ours",
                 tip="One-start champion 4.01 m. Ceiling 4.25 m from its 6.6 m/s approach."),
            dict(label="Elite, literature", sub="32 fresh starts", value=F("long_jump_elite2_robust32"), ceiling=4.25, kind="ours",
                 tip="Starts never used in practice: 31 of 32 legal. The 16-start champion scores 3.0–3.2 m on fresh starts."),
            dict(label="Elite, old profile", sub="16 starts, provisional", value=F("long_jump_elite_robust"), kind="ours",
                 tip="Uses the elite profile whose muscle strengths were set too high, with the older take-off practice."),
            dict(label="Untrained women", sub="reference", value=3.57, kind="ref", tip="3.57 ± 0.54 m (Romdhani et al. 2026)"),
            dict(label="Untrained men", sub="reference", value=4.95, kind="ref", tip="4.95 ± 0.55 m (Romdhani et al. 2026)"),
            dict(label="High-school qualifying", sub="reference", value=6.36, kind="ref",
                 tip="Boys 6.07–6.65 m (Oregon 2026 state standards). Jumpers aged 14–28 run up at 8.89 m/s (Bayraktar & Cilli 2018)."),
            dict(label="College finals", sub="reference", value=7.66, kind="ref", tip="NCAA D1 finals medians 7.56–7.75 m"),
            dict(label="World record", sub="reference", value=8.95, kind="ref", tip="Powell 1991; run-up 11.0 m/s"),
        ],
        "Bars are means over the arena starts (16 perturbed starts, or the single nominal start). Outlines are the ideal-control take-off ceiling for that runner's own approach.")

    ch_bat = chart(
        "c-bat", "Bat speed at contact", "m/s", 40, [0, 10, 20, 30],
        [
            dict(label="Hitch-free swing (v5)", sub="before", value=13.86, kind="ours", tip="24 pitches it never saw. Its arm drive was limited by its plan."),
            dict(label="Codex pure search", sub="independent", value=14.79, kind="ours", tip="Keeps the pause before and after contact."),
            dict(label="Contraction knots, before tuning", sub="newer pitch set", value=19.44, kind="ours",
                 tip="Knots distilled from the fast swing, reflexes on, on the 24 newest held-out pitches: 20 of 24 hit, the four misses all low pitches. On the earlier set of 24 it scored 21.57."),
            dict(label="Contraction knots, tuned on fresh pitches", sub="new champion", value=F("bat_power_fresh_rep"), kind="ours",
                 tip="Reflexes on. Tuned by two sep-CMA searches on 16 fresh training pitches that no arena trial uses. All 24 held-out pitches hit and pass the hitch guard; 48 of 48 hit on another 48 fresh pitches at 26.37."),
            dict(label="Open-loop program", sub="ceiling study", value=25.24, kind="study",
                 tip="Excitation program, reflexes off. 24 of 24 hits. Built from 6 of the 18 grid pitches; the 24 fresh pitches are held out."),
            dict(label="MLB average", sub="reference", value=32.0, kind="ref", tip="About 72 mph at the sweet spot (Savant 2024)"),
        ],
        "Athlete body (strength ×1.5, pivot root). All bars are scored on 24 fresh pitches that no swing was trained on; the two contraction-knots bars use a newer set than the others.",
        legend_ours="Swing with reflexes on")

    ch_tt = chart(
        "c-tt", "Table tennis, phase 2", "%", 100, [0, 25, 50, 75, 100],
        [
            dict(label="Robolab, all serves", sub="300 serves", value=round(100 * F("tt_p2_300"), 1), kind="ours",
                 tip="Forehand serves 36–46%, backhand serves 23%."),
            dict(label="Robolab, backhand serves", sub="131 serves", value=round(100 * F("tt_p2_backhand"), 1), kind="ours",
                 tip="The backhand works, but weakly."),
            dict(label="Challenge winner", sub="reference", value=64, kind="ref", tip="2025 MyoChallenge phase 2"),
            dict(label="Best reported", sub="reference, preprint", value=80.3, kind="ref",
                 tip="Diff-Muscle (Zhao et al., arXiv 2603.08617, Mar 2026), a preprint; up to 14 dual-agent rally exchanges."),
        ],
        "MyoChallenge phase-2 success rate: the share of serves the task scores as solved.",
        target=dict(v=90, label="Goal 90%"))

    charts = f'<div class="chartgrid">{ch_sprint}{ch_jump}{ch_bat}{ch_tt}</div>'

    # ------------------------------------------------------------ ability cards -----
    run_cards = [
        card("run-natural", "Natural running from human keyframes", [chip("done", "Champion, 12 starts")],
             [vid("run_knots.mp4", out("run_knots.mp4"), "Natural runner with the literature curves ghosted",
                  "12 s of the current runner. The literature gait curves are ghosted at the current stride phase.")],
             ["Contraction keyframes at touchdown, mid-stance and toe-off from human running data, eased through and latched on the feet. The latest version adds a knot at each gait event (a contraction, a velocity and an acceleration for every muscle), fitted to the target by least squares and then improved from stride-by-stride error curves (iterative learning control).",
              "Against the literature curves it is now **7.3°** from human running on the 12-start trial: 11 of 12 starts stay up (the old runner also falls on one), and the 11 that stay up are all better than before. On the harder 48-start trial it is 7.2° on the starts that stay up, with 13 falls against 17, which is not significant. Against motion-capture running (Fukuchi 2017) it is 10.1° and falls on 11 of 48 fresh starts where the earlier runner fell on 17. Against your keyframe set 3, the keyframe-chunk runner falls on 1 of 48 fresh starts without the heel-rise keyframe at 30% of the stride (6 with it), with the pose 2.2° further from your set."],
             table(["Target (fresh starts, paired p)", "Before", "Now"],
                   [["Literature curves (12, p 0.0005)", "#1 fall, 9.13°", "#1 fall, 7.29°"],
                    ["Literature curves, harder trial (48, p 0.17, not promoted)", "#17 falls, 9.22°", "#13 falls, 7.22°"],
                    ["Motion capture (48, p 0.0498)", "#17 falls, 11.0°", "#11 falls, 10.09°"],
                    ["Your set 3, champion change (48, p 0.0095)", "#9 falls, 17.56°", "#1 fall, 19.78°"]]),
             "Train the small learned correction (a convolutional network on proprioception) for the literature and set-3 runners, where the knots alone fall on 8 and 7 of 48 held-out starts. On the mocap runner it cut held-out falls from 14 to 4 of 48 at its best checkpoint (7 at the last).",
             body="v2 anatomy, average adult."),
        card("sprint", "Sprint", [chip("run"), chip("study", "v4: three bodies in")],
             [vid(*(("sprint_v4_p95_gear4.mp4", out("sprint_v4_p95_gear4.mp4"), "Four-gear sprinter on the calibrated v4 body, 95th percentile",
                     "The four-gear champion on the calibrated v4 body, 95th percentile, from a standing start: a crouched, high-cadence start, then longer strides as the speed passes 6.5, 7.0 and 7.7 m/s.")
                    if os.path.isfile(out("sprint_v4_p95_gear4.mp4")) else
                    ("sprint_v4_p95.mp4", out("sprint_v4_p95.mp4"), "Sprinter on the calibrated v4 body, 95th percentile",
                     "The earlier one-gear champion on the calibrated v4 body, 95th percentile, from a standing start: a crouched, high-cadence gait.")
                    if os.path.isfile(out("sprint_v4_p95.mp4")) else
                    ("sprint_p95_ri.mp4", out("sprint_p95_ri.mp4"), "Sprinter on the 95th-percentile body, 7 m/s",
                     "The champion on the 95th-percentile v3 body from a standing start.")))],
             [f"Full drive on the prime movers, with the opposing muscles scaled down as their partners fire (reciprocal inhibition, k 0.5), latched on each foot. On the calibrated v4 body the 95th-percentile runner reaches **{v4p95 or '–'} m/s** ({passes('sprint_top_speed_v4_p95') if v4p95 else 'not entered'}) with four gears, the literature elite body {v4e2 or '–'} with three and the average body {V('sprint_top_speed_v4')} with three. On the older v3 body the same design reaches {V('sprint_top_speed_p95')}, {V('sprint_top_speed_elite2')} and {V('sprint_top_speed')}. The inhibition is worth +0.12 m/s on every start (v3, 95th percentile), and without it the gait falls in 4.4 to 5.6 seconds.",
              "An earlier ceiling of about 10.2 m/s for the 95th-percentile body rested on an ideal torso stabiliser that applies up to 3.9 kN·m in a 0.12 s stance, where the stance hip's muscles give at most 185 N·m. Ceilings are now computed with the torso free. On the original body that put the average runner's ceiling at 6.89 m/s, below the 7.8 of recreationally active adults, so the body model was calibrated against published data (the v4 body, below). On v4 the ceilings are 8.2, 10.45 and 9.28 m/s.",
              (f"The v4 95th-percentile runner is at {100 * F('sprint_top_speed_v4_p95') / 10.45:.0f}% of its ceiling, the average-body runner at {100 * F('sprint_top_speed_v4') / 8.2:.0f}% and the elite runner at {100 * F('sprint_top_speed_v4_elite2') / 9.28:.0f}%. The average-body gait was found by starting the search from the 95th-percentile gait (it replaced a straight-leg 4.65 m/s gait). " if v4p95 else "") + "One parameter set cannot both accelerate a standing body and cruise: a gait tuned from flying starts at top speed ran 0.5 m/s faster and falls from a standing start. So every tunable has a twin per gear, and above a speed (6.5, 7.0 and 7.7 m/s for the 95th-percentile runner) the whole stride is rebuilt from the next gear's values at the next flight; each gear is searched from flying starts recorded on the gear before it. The gains per gear were +0.45, +0.41 and +0.05 m/s. Falls on 40 unseen starts, two seed sets: average 0 and 5 (four of them at 5-7 s), 95th percentile 2 and 1, elite 1 and 2.",
              "Why not 10 m/s: at its best the 95th-percentile runner is in contact for 0.102 s, flies for 0.139 s and takes about 4.15 steps a second of about 1.9 m, with mean and peak ground force of 2.35 and 4.5 body weights. The ideal at the 10.45 ceiling is in contact for 0.100 s, flies for 0.161 s and takes 3.83 steps a second of 2.61 m, at 2.61 and 5.06 body weights. Force and contact time are within 10% of the ideal, but the runner flies 14% less and steps 27% shorter. The search never adopted the ideal stance because the extended stance falls in acceleration on 60% of standing starts: no controller here holds the trunk against the stance hip's extension torque (it pitches 0.36 rad per stance, against the ideal's 0.1 rad)."],
             table(["Body", "Best on v3", "v3 ceiling", "v4 runner", "v4 ceiling"],
                   [["Average", f"#{V('sprint_top_speed')}", "#6.89", f"#{V('sprint_top_speed_v4')}", "#8.2"],
                    ["95th percentile", f"#{V('sprint_top_speed_p95')}", "#9.69", "#" + (v4p95 or "–"), "#10.45"],
                    ["Elite, literature", f"#{V('sprint_top_speed_elite2')}", "#8.5", "#" + (v4e2 or "–"), "#9.28"]]),
             "Harden the start phase (the elite runner falls in about 7% of 70 fresh starts within 14 s, the average one in about 3%). For 8 m/s on the 95th-percentile body, a robust fifth gear or an extended-stance search from flying starts; the hazard above 7.7 m/s is the limit. 10 m/s needs 96% of the ceiling.",
             body="Average, 95th percentile and literature elite bodies: the calibrated v4 body for the newest runners, the v3 anatomy for the older ones."),
        card("blocks", "Sprint from blocks, keyframed on Usain Bolt", [chip("done", "Champion"), chip("study", "About 2x Bolt's time")],
             [vid("sprint_blocks.mp4", out("sprint_blocks.mp4"), "Start from blocks with Bolt's pose ghosted",
                  "Bolt's pose is ghosted over the runner. No broadcast frames are shown.")],
             ["Keyframes measured from side-view footage of Bolt at block exit, the first steps and the max-velocity cycle. The set position is the mean of the 2018 World Indoor 60 m finalists, and steps 3 to 10 are interpolated. The runner sets on two angled pads, pushes off the rear pad on its force, then the front pad, then accelerates through steps blended from Bolt's first steps into his max-velocity cycle. Reaction time is 0.237 s.",
              f"On the 95th-percentile body it covers 30 m in **{V('sprint_blocks_30')} s** and 100 m in **{V('sprint_blocks_100')} s** on 11 of 12 arena starts. Bolt ran 3.78 s and 9.58 s, so this is about twice his time and 4 to 6 s behind a recreational sprinter: 3.3 steps a second of 1.7 m against his 4.5 of 2.4 to 2.7 m. The same controller on the average body falls on every start. At touchdown its trunk leans about 30° more than Bolt's upright 4°."],
             None,
             "Reuse this start for the hurdler. It has not been moved to the v4 body yet, where sprinters now exist (the four-gear runner reaches 7.9 m/s from a standing start).",
             body="95th-percentile body only: the average body cannot leave the blocks."),
        card("touch", "Touch-only sprint", [chip("done", "Champion, fast-running trial")],
             [vid("sprint_touch.mp4", out("sprint_touch.mp4"), "Sprint from a single touchdown keyframe", "Muscles are tinted by activation.")],
             ["Your idea of keyframing only the toe-touch. One right-touchdown keyframe (the left is its mirror), each stride one spline from touch to touch, with the joint velocities at the touch, and full-power bursts timed on each leg's own touchdown and toe-off. Without the velocities every version fell within two steps.",
              "It took over the fast-running trial (a naturalness score at 5 m/s): 10 of 12 starts stay up where the old champion failed all 12. The quadriceps pulse at landing alone is worth 0.7 m/s. It runs 4.6 m/s on the average body against 5.0 for the tuned sprinter."],
             None, None,
             body="v3 anatomy, average adult."),
    ]

    def lj_caption(metrics_path, lead):
        try:
            m = json.load(open(os.path.join(ROOT, "out", metrics_path)))
            by = {"l_foot": "left foot", "r_foot": "right foot", "l_hand": "left hand", "r_hand": "right hand"}.get(m.get("nearest_mark_by"), "the body")
            tail = " The jumper falls over after landing." if m.get("flipped") or m.get("fell_back") else ""
            return f"{lead} {m['official_m']:.3f} m; the nearest mark is the {by}.{tail} Take-off, flight and landing play at quarter speed."
        except (OSError, KeyError, ValueError):
            return lead
    lj_videos = []
    if os.path.isfile(out("long_jump_v7_p95.mp4")):
        lj_videos.append(vid("long_jump_v7_p95.mp4", out("long_jump_v7_p95.mp4"), "Long jump, one-start champion",
                             lj_caption("long_jump_v7_p95_metrics.json", "The one-start champion (oracle-class landing, overfit to this start):")))
    else:
        lj_videos.append(vid("long_jump_v6_p95.mp4", out("long_jump_v6_p95.mp4"), "Long jump on the 95th-percentile body, 4.96 m",
                             lj_caption("long_jump_v6_p95_metrics.json", "The one-start champion of the morning of 29 Sep:")))
    if os.path.isfile(out("long_jump_v5_v4p95.mp4")):
        v4_video = vid("long_jump_v5_v4p95.mp4", out("long_jump_v5_v4p95.mp4"), "First long jump on the calibrated v4 body",
                       lj_caption("long_jump_v5_v4p95_metrics.json", "The first jump on the calibrated v4 body (one start, not robust):"))
    else:
        v4_video = None
    if os.path.isfile(out("long_jump_v7_p95_robust.mp4")):
        lj_videos.append(vid("long_jump_v7_p95_robust.mp4", out("long_jump_v7_p95_robust.mp4"), "Long jump, robust champion, start 401",
                             lj_caption("long_jump_v7_p95_robust_metrics.json", "The robust champion on one of its 16 arena starts (seed 401):")))
    if v4_video:
        lj_videos.append(v4_video)

    jump_cards = [
        card("longjump", "Long jump", [chip("run"), chip("study", "Oracle-class programs")],
             lj_videos,
             ["The run-up is the sprint champion itself. World Athletics rules are in the score: foul line on every tick of the stance, no somersault past 120° until landing is over, no touching the runway after landing, and the mark is the nearest break in the sand by any body part. The take-off comes from an ideal-control analysis of the runner's own approach, distilled into contraction knots latched on the plant touchdown.",
              f"That took the 95th-percentile body from 3.68 m to 4.895 m on one start (99% of that start's 4.93 m ideal take-off; the 7.02 m/s runner). A landing program learned for that one start then took it to **{V('long_jump_p95', 3)} m**, with the mark 0.37 m beyond the centre of mass's ballistic 4.75 m. That landing is an open-loop excitation table on a clock locked to the predicted landing, so it is oracle-class and overfit to the start by construction.",
              f"The robust champion, over 16 perturbed starts, went from 3.22 m to 3.92 m and now to **{V('long_jump_p95_robust')} m**: an ideal-control take-off launched from the penultimate touchdown, a plant latch at 1.5 body weights, a swing-foot lag feedback, and a landing program learned on 32 hand-overs, on a ballistic-time clock (the landing program's clock used to start at the hand-over, so a slightly lower or slower flight landed 30 to 50 ms early with the legs still hanging and the body vaulted over its feet). Both programs are near open loop (reflex gain 0.03), so this one is oracle-class too. On starts no search ever used it scores {V('long_jump_p95_robust32')} m over 32 (31 legal) and {V('long_jump_p95_robust96')} m over 96 (89 legal); a separate check of 384 fresh starts gave 95.8% legal, 2.3% somersaults and a 4.48 m mean, and the 28 Sep champion scored 3.27 m on the first 96. The literature elite body reaches {V('long_jump_elite2_robust32')} m over 32 fresh starts (31 legal), up from 3.01 m.",
              f"The first jump on the calibrated v4 body (7.0 m/s runner, ideal take-off 4.89 m) was 4.945 m on one start. With the two-gear runner (6.58 m/s over the last 5 m at a 44 m check mark, was 6.40) and an ideal take-off learned for that start (5.219 m ballistic from the foot, open-loop excitations of all 32 muscles, oracle-class), the one-start jump is {V('long_jump_v4_p95', 3)} m. The robust stage (milestone M1: hip-nudge run-up steering, an upright final approach, a take-off program fitted over 32 gap-stratified approaches of both plant sides and a landing program learned on 62 hand-overs, all near open loop, oracle-class) scores {V('long_jump_v4_p95_robust32')} m over 32 fresh starts and {V('long_jump_v4_p95_robust96')} m over 96 (the earlier programs: 2.85 and 2.54); the 16-start trial still holds its older {V('long_jump_v4_p95_robust')} m. The average body reaches {V('long_jump_robust')} m robust and 2.47 m on one start."],
             table(["Body", "One start", "16 starts", "Ideal take-off"],
                   [["Average", "#2.47", f"#{V('long_jump_robust')}", "#–"],
                    ["95th percentile", f"#{V('long_jump_p95', 3)}", f"#{V('long_jump_p95_robust')}", "#4.93"],
                    ["95th percentile, v4", f"#{V('long_jump_v4_p95', 3)}", f"#{V('long_jump_v4_p95_robust')} (provisional)", "#5.22"],
                    ["Elite, literature", f"#{V('long_jump_elite2')}", f"#{V('long_jump_elite2_robust')}", "#4.25"],
                    ["Elite, old profile (provisional)", f"#{V('long_jump_elite')}", f"#{V('long_jump_elite_robust')}", "#–"]]),
             "Against people: the one-start 5.12 m is 103% of the untrained-man mean; the robust jump is 87 to 92% of it on fresh starts and sits inside the speed-matched elite range (4.33–4.77 m from 6.1–6.6 m/s, Bridgett & Linthorne 2006). Nobody reaches the high-school state level: the take-off vertical speed is already 3.0 m/s, so speed is what is missing. Next: a robust stage for the elite body over its 159 mined plant-flight states, the v4 take-off foot within 0.05 m of the line, and run-up speed.",
             body="v3 anatomy, 95th percentile (elite variants: the elite and elite2 profiles); the calibrated v4 anatomy for the new v4 jump."),
        card("standing", "Standing broad jump", [chip("done"), chip("study", "Codex policies")],
             [vid("codex_standing_jump.mp4", CODEX + "competitor_jump_round2__video_search_jump_legal_tcn.mp4", "Standing jump champion, 1.363 m",
                  "The legal-distance champion, 1.363 m (Codex, round 2): it lands and stays on its feet."),
              vid("codex_jump_robust_r7.mp4", CODEX_ROOT + "out/competitor_jump_round7/video_search_jump_robust_legal_tcn.mp4", "Robustness champion, 1.34 m",
                  "The 32-start robustness champion (Codex, round 7): 1.341 m on seed 3024, legal through 20 s.")],
             [f"Contraction keyframes with take-off and landing latched on the centre of mass. The legal-distance champion is Codex's temporal recovery policy at **{V('search_jump_legal', 3)} m** (8 starts): a small learned correction after landing that keeps the jumper on its feet. On the 32 larger nudges the champion is now Codex's round-7 policy: **{V('search_jump_robust_legal', 3)} m** with {passes('search_jump_robust_legal')} landing at the arena's 3 s horizon. It replaced our convolutional keyframe policy (1.315 m) here on 29 Sep after your go-ahead, and it reproduced Codex's own score exactly.",
              "On Codex's own fresh starts our old policy was legal at 3 s on 64 of 64 but at 8 s on 0 of 64, while the round-7 policy is legal at 8 s on 57 of 64. Its distance on the 8-start trial (1.349 m) does not beat the legal-distance champion (p 1.0)."],
             None, None,
             body="Planar v3 body."),
        card("hurdles", "Hurdles", [chip("stuck", "Waiting on run-up")],
             [vid("hurdle_hs_076.mp4", out("hurdle_hs_076.mp4"), "Hurdler at 0.762 m", "Hurdle height 0.762 m (2 ft 6 in).")],
             ["Lead knee driven up and extended over the bar, the trail leg lifted out to the side and turned so the knee comes around. At your high-school height of 0.991 m the lead leg clears and the trail leg catches the bar at the first hurdle, so nothing is cleared. At the curriculum's lowest step, 0.762 m, it clears the first hurdle on 4 of 8 starts and then falls before the second.",
              "The run-up is the limit: about 4 m/s at the first hurdle where a high-school hurdler arrives near 7. The start from blocks reaches 5.0 m/s at 13.7 m, on the 95th-percentile body."],
             None, "Rebuild the approach on the blocks start and, later, the v4 sprinter; then work the trail leg.",
             body="v3 body with 3D hips (hip abduction and rotation freed)."),
    ]

    ball_cards = [
        card("bat", "Baseball swing", [chip("run"), chip("study", "Ceiling study shown")],
             [(vid("bat_r2_s1.mp4", out("bat_r2_s1.mp4"), "Swing with contraction knots, reflexes on, tuned on fresh pitches",
                  "The first tuned version, in robolab's representation (contraction knots, reflexes on): 25.7 m/s on 24 held-out pitches, all hit. The current champion reaches 26.2.")
               if os.path.isfile(out("bat_r2_s1.mp4")) else
               vid("bat_v6_knots.mp4", out("bat_v6_knots.mp4"), "Swing with contraction knots and reflexes on",
                  "In robolab's representation (contraction knots, reflexes on): 21.6 m/s on pitches it never trained on.")),
              vid("bat_v6.mp4", out("bat_v6.mp4"), "Open-loop ceiling swing",
                  "Ceiling study: an open-loop excitation program with the reflexes off, 25.2 m/s.")],
             ["The earlier hitch-free swing was slow because of its plan. The arms and wrists fired at full power only 2 to 8% of the swing, the bottom wrist cast early, and the bat peaked 42 ms before contact. The fast swing turns the pelvis at full drive into its yaw limit, keeps the spine coiled, fires short arm bursts with no co-contraction, and whips the bottom wrist through 0.8 rad in the last 60 ms. That wrist runs at 1,069 °/s in the open-loop program and 930 °/s in the reflex-on swing; college hitters manage 1,093 ± 354 (lower hand).",
              "The open-loop program scores 25.2 m/s on 24 fresh pitches and hits all 24. It was built from 6 of the 18 grid pitches (their locations at 76 mph), so the 24 fresh pitches are the held-out test. Distilled into contraction knots with the reflexes on, it kept 82 to 85% of that speed (21.6 m/s, 2 to 4 of 24 pitches missed by 1 to 3 cm), and on a newer set of 24 held-out pitches it scored 19.4 m/s and hit 20 (the four misses were all low pitches, 0.64 to 0.67 m up). Landing the step 62 ms later had cut the pause before the swing from 115 ms to 50 ms.",
              f"Retuned by sep-CMA on 16 maximin fresh training pitches that no arena trial uses (23 tunables: arm reflex damping 0 instead of 0.099, the swing fired 9 ms earlier and its train 20 ms longer so contact comes at 223 ms instead of 217, and the train gain, arcs and gains), the swing in robolab's own representation first scored 25.7 m/s on the 24 held-out pitches. A second search over 32 tunables (the reflex targets read 18 ms ahead of the drive, the swing fired 12 ms earlier than the v6 knots, the train 30 ms longer with the plan carried on past the program's contact, the first knot segment 1.35 times, the aim-correction gains) took it to **{V('bat_power_fresh_rep', 2)} m/s**: all 24 held-out pitches hit and all pass the hitch guard (flow 2.48). On 48 further fresh pitches it hits 48 of 48 at 26.37 m/s (flow 2.44, at most 2.91). The first tuned swing beat the earlier knots swing by 6.27 m/s on the held-out set (p below 0.001). It is not an open-loop program: the contraction knots and the reflex layer are in the loop."],
             table(["Swing", "18 test pitches", "24 new pitches", "24 newer pitches"],
                   [["Hitch-free (before)", "#13.78", "#13.86", "–"],
                    ["Codex pure search", "#14.72", "#14.79", "–"],
                    ["Reflexes on, knots", "#23.1–24.5", "#20.6–21.6", "#19.44"],
                    ["Reflexes on, tuned on fresh pitches", "–", "–", f"#{V('bat_power_fresh_rep', 2)}"],
                    ["Open-loop program (ceiling study)", "#25.17", "#25.24", "–"]]),
             "More residual searches are running (drive shape, time bumps, a convolution readout), and a look at what limits the trunk and the elbows.",
             body="Athlete body: strength ×1.5, every muscle's peak speed 3.0 L0/s, a pivot root with a yaw hinge and a slide, no whole-body balance. On the human-calibrated body at strength 1.0 the champion is 10.3 m/s."),
        card("dribble", "Dribbling", [chip("run")],
             [vid("dribble_btl.mp4", out("dribble_btl.mp4"), "Three passes through the legs in a row",
                  "Through the legs: three passes in a row on a start found by scanning seeds, with a slow-motion replay of the pass."),
              vid("codex_crossover.mp4", CODEX_ROOT + "out/competitor_dribble_round9/video_dribble_crossover_25_tcn.mp4", "Crossover dribble, Codex champion",
                  "Crossovers: Codex's round-9 champion, 9.08 per 15 s run. The ball is still lost eventually on every run.")],
             [f"**Through the legs.** A stance planner picked a staggered lunge with the trunk twisted toward the lead leg, and catch spots that both hands can reach from behind the ball. On the 25 arena starts the mean longest streak is {V('dribble_btl_streak_25', 2)} passes in 15 s and never more than {streak_max}; {btl_any} of {btl_n} starts get at least one good pass and {btl_two} get two in a row. The agent's own 8 s check on 24 fresh starts (not saved as a trial) had the first pass complete on 22 (92%), the return on 10 (42%), and 33 of 61 passes good, with a streak of 3 on only 1 or 2 of 32 fresh starts. The earlier \"between the legs\" video was a low crossover in front of the lead foot: the ball never went through the gap, and the leg-gate count for it is 0 on all 25 starts.",
              "**Crossovers.** Codex's small learned correction from the recent ball motion doubled the count from 3.72 to 7.52 per 15 s run, and its round-9 version (sustained catching) took it to 9.08 (+1.56, p 0.006, promoted here on 29 Sep). The trunk still pumps and the hands are rigid paddles."],
             table(["Trial", "Champion", "Was"],
                   [["Through the legs, 25 starts (good passes ÷ max(attempts, 10))", f"#{V('dribble_btl_25', 3)}", "#0.000"],
                    ["Through the legs, longest streak (mean of 25)", f"#{V('dribble_btl_streak_25', 2)}", "#–"],
                    ["Crossovers per 15 s run, 25 starts", f"#{V('dribble_crossover_25')}", "#7.52 (3.72 before)"]]),
             "The return pass: the arms can stop a fast, flat ball but cannot follow it down and drive it back up, and they lag the plan. Try catching it while it is still rising, catch spots about 25 cm closer, and a trunk turn into the catch.",
             body="Stationary pivot bodies. Through the legs: the v3 body. Crossovers: the v1 body with rigid paddle hands."),
        card("tt", "Table tennis", [chip("stuck")],
             [vid("myo_tt_r5.mp4", out("myo_tt_r5.mp4"), "Five solved serves in a row",
                  f"Five solved serves in a row (seeds 98045 to 98049) by an earlier phase-2 champion. The current champion solves {100 * F('tt_p2_300'):.0f}% of serves, so this is a chosen streak, not a rally."),
              vid("myo_tt_strokes.mp4", out("myo_tt_strokes.mp4"), "Chop, wrist flick and low scoop",
                  "Chop, backhand flick and low forehand scoop with real ball spin, at the best angles found.")],
             [f"Predicts the ball through the bounce, slides the pelvis onto its path, latches the ready posture on time-to-paddle and sets the paddle face from an aim law. Phase 1 is 100%. Phase 2 is **{100 * F('tt_p2_300'):.0f}%** over 300 serves (33% this morning), and the winner scored 64%. Round 10 re-tuned the backhand with a bounce-tick guard, a 17-factor screening design and response-surface runs: on 900 fresh serves the champion's 30.2% became 37.7% (backhand 21.8% to 35.9%, p below 0.005 on both blocks), and the arena's 300 serves went from 33.0% to 40.0% (p 0.002). A later variant (c5) does better still on fresh serves (900: 40.9%) but the arena cannot tell it from the champion (121 against 120 of 300, p 0.5): the arena's 300 seeds flatter the old champion.",
              "The gain came from one defect. On the single tick when the table-contact flag is set the ball's velocity is mid-reversal, and the skill predicted the pad-plane crossing from it as if it were the bounce's outcome, so for that tick the plan was 0.3 to 1.6 m off on every serve (fixing it alone lifts the hit rate from 0.80 to 0.87), and it had hidden a small retreat that the champion depended on, which a late pelvis kick now restores on purpose. The ceiling is set by the arm: pad pitch 10° (1 sigma), pad velocity 0.5 m/s and a 5 cm miss of the sweet spot cap even a perfect plan near 45%, against 90% needing about 4°, 0.25 m/s and 3 cm at once. Fast serves are hit but come back too fast: above 5.5 m/s only 8 to 13° of pad pitch return a ball that clears the net and lands.",
               "The aim is accurate. The arm does not carry it out: a forehand asked to turn its forearm 1.20 rad reaches 0.44, and the face follows 0.53 to 0.66 of an aimed change on the forehand and 0.13 to 0.28 on the backhand (1 would be perfect). Live moment arms fix the arm's tracking (backhand error 0.80 to 0.21 rad, forehand yaw follow 0.66 to 1.01), but the tracked arm plays like a new player and needs a long practice run. Where the ball meets the paddle decides most forehands: 67% solved within 3 cm of the centre, 1 in 7 on the rim.",
              "Your strokes: the chop goes high because the aim rule opens the forehand face about 40° and the forehand path cannot get steeper than about 40° down. The best chop is the backhand, commanded at a 60° face and a 40° downward path, which reaches −4° and 33° down (4 cm over the net, 11 rev/s of backspin, 3 of 11 landed). The wrist flick makes topspin, under 5 rev/s, because its paddle reaches only 1.3 to 1.5 m/s."],
             None,
             "Finished (agent T): 90% is out of reach for this arm. A trial with 600 or more fresh serves would settle c3 against c5. 90% is 10 points above the best reported result (80.3%, a preprint) and 26 above the challenge winner.",
             body="The official MyoSuite table-tennis body: 273 muscles and 2 pelvis actuators."),
    ]

    soccer_cards = [
        card("balance", "One-leg balance", [chip("run")],
             [vid("soccer_balance_300.mp4", out("soccer_balance_300.mp4"), "Standing on one leg for the first 40 seconds of a 298 second hold",
                  "The first 40 s of a 298 s one-leg stance on the 290-muscle body (the earlier champion; the hold itself is unchanged).")],
             [f"The hold is steered by the sensed centre of pressure, with a slow centring loop and per-posture muscle moment arms. The centring loop is what carries a hold past 96 s. On the 40-start strict trial (310 s episodes), **{bal40_hold} of {bal40_n}** fresh stances stay on one leg for at least 300 s, against 24 of 40 for the previous champion. The new champion has the lift into single support tuned (sep-CMA on an 8 s proxy, 16 fresh starts per generation). On the older 20-start trial the previous champion holds 12 of 20, and the same lift scored 15 of 20 there (p 0.23). The short two-leg trial (3 s on each leg, at most 6) went from 1.96 to 3.08 s, with the right leg still the weak one (0.63 s). The routine also holds the right leg first: 8 of 8 starts hold 310 s.",
              "Round 4 overturned the first diagnosis: in single support the standing foot's heading stays within 0.02 rad, so it does not spin. What was wrong was the controller's hip model, measured at the start posture: the gluteal muscles' moment arms change sign where one-leg stance happens (one muscle's rotation torque per unit activation runs from −29 to +37 N·m). On the 20 starts every failure was at the lift: the swing foot leaves the ground still carrying 20 to 40% of body weight, which throws the capture point 5 to 6 cm outward, past the ±2 cm the sole can absorb. On 40 new starts, 5 fell within 20 s: one in the lift, one in the set, three in the hold after the lift, where the pelvis yaw sits at the stance hip's stop, goes into a 0.75 s limit cycle and the frontal plane then runs away.",
              "Round 8 found the cause of most early falls: an over-shift. At the first lift tick the stance foot's lateral capture point separates the outcomes: 0 of 212 lifts fell with it at or inboard of the foot centre, 11 of 28 fell with it outboard (240 starts). The feed-forward shift moves the body's centre the same amount whatever the stance width, so a wide stance overshoots. Waiting for the capture point to return is fatal (0 fixed, 13 broke: they fall in the shift). A capture-point brake inside the shift fixed 11 of 11 failing outboard starts, and on unseen starts took 112 to 119 of 120 holding 20 s (p 0.02). The 310 s trial did not reward it (35 of 40) because of blow-ups: MuJoCo reports 'Nan, Inf or huge value in QACC' inside a motionless hold, the posture constant to 3 decimals for 130 s, in 7 of 120 arena runs. Every hold carries a steady 215 N shank-against-thigh contact (1.1 mm penetration, 40 of 40 starts) and a swing-ankle limit cycle; neither was shown to cause it, and candidates with less contact lose hold robustness. A challenger now needs 5 fixes and 0 breaks to be promoted (p 0.031), and one blow-up among the 34 kept starts loses it.",
              "Round 9 found the cause of the blow-ups. At the failing step exactly one muscle length is NaN: the swing leg's right rectus femoris, whose line wraps a cylinder at the knee. MuJoCo's wrap code takes the arccosine of the dot product of the two tangent points; when the muscle line only grazes the cylinder (within about a nanometre of the tangent) the points are 2e-8 rad apart, the dot rounds above 1.0 about one time in ten, and the NaN goes on to the muscle force and the whole acceleration. The swing-leg muscle hovers at that tangent and crosses it hundreds of times, so a hold is a lottery of about 0.1 per visit: it looked rare and chaotic. The contact, the solver and the time step were excluded (the NaN survives every one of them; only wrap-geometry changes remove it), and the same reproduction gives the same NaNs on MuJoCo 3.2.7, 3.3.0, 3.6.0 and 3.14.0. A guard that redoes the substep after a nudge of at most 1e-10 rad is bit-identical to the official environment until a NaN, and every one of the 10 events it met was survived. Guarded, the ranking flips (lift 35, ramp 39, shift brake 40 of 40 in the five-minute trial): the brake had lost five holds to the bug, while the lift's five falls are real balance falls. On 120 fresh starts at 20 s the ramp beats the lift (113 against 102 of 120, p 0.006) and the brake holds 118. The ramp family parks the swing leg's rectus femoris at the tangent about three times as often as the lift, which explains its unlucky official counts.",
              "A second victim turned up in the guarded runs: a trunk muscle on another wrap cylinder went NaN at 2.1 s in start 96029, which the official environment would score as a balance failure."],
             table(["Entry on the 40-start trial", "Holds 300 s, official", "Holds 300 s, guarded", "Guarded, paired p over the lift"],
                   [["Round-4 hold (seed)", "#24 of 40", "–", "–"],
                    ["Round-5 lift (champion)", "#34 of 40", "#35 of 40", "seed"],
                    ["Lift + shorter set ramp", "#38 of 40", "#39 of 40", "#0.066 (fixed 4)"],
                    ["Lift + shift brake", "#35 of 40", "#40 of 40", "#0.034 (fixed 5, broke 0), promoted"]]),
             "The upstream MuJoCo report is ready in playground/repros (a minimal reproduction and a one-line fix); filing it is your decision. Balance work should use the guarded trials.",
             body="The official MyoSuite soccer body, 290 muscles."),
        card("soccer", "Penalty kick", [chip("done", "Phase 1 champion"), chip("stuck", "Phase 2 blocked")],
             [vid("myo_soccer.mp4", out("myo_soccer.mp4"), "Penalty kick, phase 1", "Phase 1: 100% of 50 starts."),
              vid("soccer_p2_v4.mp4", out("soccer_p2_v4.mp4"), "Phase 2 attempt", "Phase 2 attempt: one step, then a fall.")],
             ["Shift weight, step, plant beside the ball, swing with a hip-flexor burst and knee snap latched on ball contact, aiming away from the keeper. Phase 1 scores every time. Phase 2 starts 0.02 to 1.4 m from that stance and lasts 10 s, and it scores 0 of 100 (the 2025 winner scored 32%).",
              "Walls, measured by two agents. The phase-1 kick is a knife-edge trajectory from one exact start. On 48 held-out starts it scores 46 with no joint noise, 18 with ±0.001 rad, 14 with ±0.002 rad and 0 with ±0.01 rad, while the official reset draws ±0.02 rad on every joint (table). The noise is not decided in the swing: it grows along the run-up (the joint vector is 0.02 rad off at 0.3 s and 0.22 to 0.30 at the plant), and the aim servo has no authority (the kicking hip's adduction sits on its 0.524 rad limit from 1.87 s to the touch). Every phase-1 kick carries 1.3 to 2.6 kN between the thighs and shanks; with the model's 14 explicit contact pairs off the champion scores 0 of 16 at zero noise, against 16 of 16 with them. The kick needs the stance to about 2 cm sideways and 5 cm fore and aft, and the official starts are within 0.15, 0.3, 0.5 and 1.0 m of the phase-1 stance for 2, 6, 20 and 77 of 100, so a perfect kick with no approach scores at most about 6 to 10. The goalkeeper is a decoy: the physics keeper stands fixed at 50 m with a 0.25 m capsule and the scoring window is a crossing 0.5 to 3.2 m to either side. From a settled stance the kick scored 0 of 30 starts even within 0.3 m of the phase-1 stance, and a staged curriculum has not scored either (the plant stage reaches 4.3 of about 13, a standing kick 1.7 m/s, the lean phase lands the foot on 1 of 6 starts). And this body cannot walk upright: the abdominal muscle's passive pull plus the upper body's weight need 84 to 123% of the back extensors' capacity whenever the chest is upright, so the chase-tag walker folds its spine within 0.5 s."],
             table(["Joint noise per reset", "Touched the ball", "Ball at least 8.5 m/s", "Goals of 48"],
                   [["None", "#48", "#48", "#46"], ["±0.001 rad", "#48", "#39", "#18"], ["±0.002 rad", "#48", "#23", "#14"],
                    ["±0.005 rad", "#41", "#9", "#8"], ["±0.01 rad", "#34", "#5", "#0"], ["±0.02 rad (official)", "#28", "#3", "#0"]]),
             "Stopped at the go/no-go gate: no closed loop closes the ±0.002 rad rung. If this line continues: a kick with the plant foot beside the ball, so the swing needs no leg-on-leg contact; a torque-space stance and heading controller for the run-up; then an approach, which needs a walking gait. A kick that needs the stance to ±0.3 m caps at 6 to 10 of the 100 starts.",
             body="The official MyoSuite soccer body, 290 muscles."),
    ]

    myo_cards = [
        small("Relocate", [chip("scored")], vid("relocate_v6.mp4", out("relocate_v6.mp4"), "Relocate, round 6",
                                               "A 295 g object from the far left, carried and held inside the box."),
              f"Official score {V('relocate_p2eval_official', 3)} on the evaluation environment (was 0.210), genuine lifts {V('relocate_p2eval_lift', 3)}. On the easier phase-2 environment, lifts {V('relocate_p2_300', 3)}. MyoSuite 2.12.2 steps a second copy of the scene whose receptacle sits at the random target, invisible to the observation, while the visible box has no walls. Scores here are not comparable to the 2023 winner's 0.343. Reported upstream as MyoHub/myosuite issue 416."),
        small("Chase tag", [chip("scored")], vid("myo_chase_v2.mp4", out("myo_chase_v2.mp4"), "Chase tag", "Two leg tracks with turning."),
              f"Phase 1 {V('chase_p1', 3)}; phase 2 {V('chase_p2', 2)} against the 2023 winner's 0.666 on the final evaluation. Each leg loops stance, push, lift and reach on its own sensed events; a step-turn loop turns toward an opponent behind."),
        small("Walking on the myoLeg", [chip("scored")], vid("myo_walk_v2.mp4", out("myo_walk_v2.mp4"), "MyoLeg walking with the longer stride", "The 80-muscle leg model with the step-length champion: 0.46 m steps at 1.44 m/s, until it reaches the arena edge."),
              f"Step length {V('walk_stride', 2)} m (was 0.36, people about 0.7), at about 1.45 m/s at any commanded speed: the longer-stride gait trades pace control for step length. Quiet standing survives 2 to 4 of 4 pushes of 60 to 80 N, not 100 N; while walking, pushes of 50 N and more knock it over."),
        small("Baoding balls", [chip("scored")], vid("myo_baoding_v3.mp4", out("myo_baoding_v3.mp4"), "Baoding balls", "Palm tilt and roll tied to the ball angle."),
              f"Score {V('baoding_p2', 3)} against the 2022 winner's 0.55. It holds both balls and nudges them but never found a rolling gait."),
        small("Die reorientation", [chip("stuck")], vid("myo_die_v3.mp4", out("myo_die_v3.mp4"), "Die", "Finger flips plus palm tilt and roll."),
              f"No full solves (0 of 100) against the co-winners' 0.13. It removes {V('die_p2_progress', 2)} rad of the die's rotation (was 0.19)."),
        small("Bimanual handover", [chip("stuck")], vid("bimanual_v4.mp4", out("bimanual_v4.mp4"), "Bimanual handover", "The arm holds the box out steadily."),
              f"Staged progress {V('bimanual_stages', 2)} (was 0.33) with no full success. The prosthesis mostly presses its hand against the held box; it is not yet a grip."),
    ]

    # ------------------------------------------------------------ bodies -------------
    bodies = table(
        ["Body", "What it is", "Sprint ceiling, torso free", "Used for"],
        [
            ["Average (v2, v3)", "Average adult. v3 adds elastic Achilles and quadriceps tendons.", "6.89 m/s on v3", "Running, standing jump, dribble, hurdles, most older results"],
            ["95th percentile", "Strength ×1.32, muscle speed ×1.2 and tendon stiffness ×1.5 (each a 95th percentile of published data), activation time constants ×0.87 (inferred; no population distribution exists).", "9.69 m/s on v3", "Sprint, blocks, long jump"],
            ["Elite, old profile", "Strengths set per muscle from memory of the papers (hip extensors ×1.6, vasti ×1.3, speed ×1.3). A check on 28 Sep found iliopsoas, vasti, soleus, gastrocnemius, the quadriceps tendon and activation set too strong.", "unverified", "Results marked provisional"],
            ["Elite, literature (elite2)", "Every part cited. Elite knee and ankle extensors sit near the untrained mean.", "8.5 on v3, 9.28 on v4", "New trials"],
            ["v4, calibrated", "v3 with two literature-backed changes: quadriceps series stiffness 250 to 1000 N/mm, hip speeds 15 to 18.5 (extension) and 29 (flexion) rad/s.", "8.2 average, 10.45 95th pct., 9.28 elite2", "Sprinters being tuned now"],
            ["Athlete (bat)", "The batter's body: strength ×1.5, every muscle's peak speed 3.0 L0/s, damping 1.5, on a pivot root with a yaw hinge and a slide. No whole-body balance.", "–", "Baseball swing"],
            ["Official MyoSuite bodies", "80 to 290 muscles on wrapped tendons, with the official environments and scoring.", "–", "Table tennis, soccer, chase tag, relocate, baoding, die, bimanual, walking"],
        ], wide=True)

    # ------------------------------------------------------------ codex --------------
    codex = table(
        ["Result", "Codex reports", "In this arena"],
        [
            ["Standing jump, legal distance (8 starts)", "1.363 m (temporal recovery)", "Run here 27 Sep: promoted. Its round-7 policy scores 1.349 here and does not beat it (p 1.0)."],
            ["Standing jump, robustness (32 starts)", "1.3397 m, 32 of 32 legal at 3 s; 57 of 64 legal at 8 s on fresh starts (R7)", "Run here 29 Sep: 1.3397 against our 1.3153, promoted. Ours was legal on 0 of 64 at 8 s on the same fresh starts."],
            ["Crossovers, 25 starts", "7.52, later 9.08 (R9)", "7.52 run here 27 Sep: promoted. 9.08 run here 29 Sep: +1.56, p 0.006, promoted."],
            ["Crossovers, 10 starts", "9.4 against 7.3 (p 0.09)", "Run here 29 Sep: the same, p 0.092, not promoted."],
            ["Dribble with the trunk quiet (arms only)", "R9 0.204 against 0.182 (p 0.50)", "Run here 29 Sep: the same numbers, not promoted (the trunk pump remains)."],
            ["Bat power", "14.72 m/s, pause before and after contact kept", "Run here 27 Sep: promoted, later beaten by the open-loop program."],
            ["Dribble rounds 10 and 11", "R10 no promotion. R11 (fingered hand) is running", "–"],
        ], wide=True)

    # ------------------------------------------------------------ running now --------
    working = table(
        ["Workstream", "Where it stands", "Next"],
        [
            ["Sprint on the v4 body (agent S, finished)", f"Final arena: 95th percentile {v4p95 or '–'} m/s with four gears (12 of 12), elite {v4e2 or '–'} with three (11 of 12), average {V('sprint_top_speed_v4')} with three (12 of 12): 73 to 76% of the ceilings. This crouched family saturates near 8 m/s (the gain per gear: +0.45, +0.41, +0.05); the agent's report says why it stops there.", "Unowned: harden the start phase; a fifth gear or an extended stance"],
            ["Long jump (agent L2, round 3)", f"Running. Milestone M1 with the two-gear runner: the robust v4 jump is {V('long_jump_v4_p95_robust32')} m over 32 fresh starts and {V('long_jump_v4_p95_robust96')} m over 96 (was 2.85 and 2.54), the one-start jump {V('long_jump_v4_p95', 3)} m, the ideal-control ceiling 5.219 m; all oracle-class. The landing search is still running.", "More landing search; the 16-start trial"],
            ["Balance and soccer (agent O, finished)", f"The 40-start champion holds {bal40_hold} of {bal40_n}; a shorter set ramp holds 38 of 40 (p 0.115) and a capture-point brake fixes almost every early fall. The late falls are MuJoCo blow-ups. Phase 2: the kick is a knife-edge trajectory, still 0 of 100.", "Blow-ups (agent K); closed-loop kick (agent P)"],
            ["Hold blow-ups (agent K, finished)", "Root cause found and reproduced: a NaN in MuJoCo's tendon-wrap code (an arccosine of a value that rounds above 1 when a muscle line grazes its wrap cylinder), present in MuJoCo 3.2.7 to 3.14.0 and in upstream main. The guarded trials (a labelled variant, bit-identical to the official one until a NaN) certify balance: the shift-brake variant holds 40 of 40 for five minutes (p 0.034) and 68 of 69 more fresh starts; on 120 fresh starts at 20 s the ramp beats the lift (113 against 102) and the brake holds 118. The upstream report is ready.", "Your decision: file the MuJoCo report"],
            ["Closed-loop kick (agent P, finished: no-go)", "The kick does not close ±0.002 rad of joint noise (14 of 48 held-out starts score, from 46 of 48 with none); the official reset noise is ±0.02 rad (0 of 48). The kick depends on a thigh-against-shank contact, needs ±2 cm sideways, and only 6 of 100 starts are within 0.3 m of the stance. Phase 2 stays at 0 of 100.", "Unowned: a kick with no leg-on-leg contact, a walking approach"],
            ["Table tennis above 90% (agent T, finished)", f"The arena's 300 serves went from 33.0% to {100 * F('tt_p2_300'):.1f}% (p 0.002): a one-tick artifact at the table bounce removed and the backhand re-tuned (21.8% to 35.9% on 900 fresh serves). c5 does better on fresh serves (40.9%) but the arena cannot tell it from c3. A perfect plan at the arm's measured noise tops out near 45%: 90% is out of reach for this arm.", "Unowned: a 600-serve trial; a quieter arm (face 4°, pad velocity 0.25 m/s, place 3 cm)"],
            ["Compiler fixes", "Done: merged into main (032bab4e5) after a full compiler build, the stage-identity check against a baseline (the same 988 differing lines as unmodified main, identical after normalising hashes) and the spec lanes with no regression. It also fixed a use-after-free with unicode parameter names.", "Rebuild the shared compiler (bin/tungsten build) to activate them"],
            ["Landing robolab on main", "Done in three steps, each after a clean-worktree check: 3c5c513e4 (the whole campaign), 08a6fe1bb (long jump round 2) and 371429c1a (sprint and soccer round 8). The last check was isolated: 5 entries built, SDK spec 93 of 93, replays equal to the recorded scores including the recorded falls, 51 other entries through the compiler front end. The first two checks read the shared checkout's sources through BIT_HOME; main's contents were re-checked isolated.", "Bat, dribble, long jump, table tennis and soccer land when their agents finish"],
            ["MyoSuite relocate bug report", "Filed: github.com/MyoHub/myosuite/issues/416, with a minimal reproduction and a two-line fix that removes the mismatch (0 of 300 starts overlapping the invisible receptacle after it, 87 of 300 before).", "Watch for a reply"],
            ["Bat speed in robolab's own representation (agent B)", f"Running. Promoted: the swing that keeps the reflex layer scores {V('bat_power_fresh_rep', 2)} m/s on 24 new held-out pitches (all hit, all passing the hitch guard), up from 19.44 for the earlier knots swing on the same pitches, and 26.37 on 48 more fresh ones. It is above the open-loop ceiling study (25.24 on an earlier set of pitches). Residual searches and a 95th-percentile-body variant are running.", "Drive shape, time bumps, a convolution readout; what limits the trunk and elbows"],
            ["Dribble through the legs (agent D)", f"Running. Mean longest streak {V('dribble_btl_streak_25', 2)} in 15 s, at most {streak_max}, on 25 starts. The wall is the return pass. Plan: a trunk turn into the catch, closer catch spots, catching the ball while it rises.", "Several passes in a row on held-out starts"],
            ["Natural runner, hurdles, relocate", "Written up in the handoff for Codex to pick up (bits/tungsten-robolab/HANDOFF_20260929.md)", "Codex chooses"],
        ], wide=True)

    working = working.replace("github.com/MyoHub/myosuite/issues/416", '<a href="https://github.com/MyoHub/myosuite/issues/416">github.com/MyoHub/myosuite/issues/416</a>')

    # ------------------------------------------------------------ requests -----------
    requests = table(
        ["You asked", "Where it stands"],
        [
            ["A natural runner: power leg extended, other knee and arm up", "Built and improved: 7.3° from human running (was 9.1°) on the 12-start trial."],
            ["Batter hitch, before and after contact", "After contact: fixed for the 13.9 m/s v5 swing (the stall was the wrist and the pelvis hitting their joint limits). The 25.7 m/s swing passes the hitch guard on all 24 held-out pitches (flow 2.64, at most 3); the earlier 21.6 m/s knots swing failed it on 2 of 24."],
            ["Dribble: a visible crossover, less back, more elbow, fingers", "Crossover 7.52 per 15 s run. The trunk still pumps. The fingered hand is built (opt-in); no evidence of a gain yet, and Codex's fingered-hand search is running."],
            ["A better long-jump run and take-off", f"{V('long_jump_p95', 2)} m on one start and {V('long_jump_p95_robust')} m over 16 perturbed starts (both oracle-class; {V('long_jump_p95_robust96')} m on 96 fresh starts). The sprinter is the run-up."],
            ["Hurdles at high-school height", "At 0.991 m: the lead leg clears and the trail leg catches at the first hurdle. At 0.762 m: hurdle 1 cleared on 4 of 8 starts. Waiting on run-up speed."],
            ["Table tennis backhand, wrist flick, chop, low scoop", "The backhand exists (23% of backhand serves solved). Chop, flick and scoop were measured with real ball spin: the best chop lands 3 of 11, the flick 0 of 20, the scoop 2 of 20."],
            ["Soccer kick with the inside of the foot", "Not yet: the best attempt strikes with the toes."],
            ["MyoLeg longer strides", f"{V('walk_stride', 2)} m (was 0.36; people about 0.7), at about 1.45 m/s."],
            ["Toe-touch and toe-off keyframes only, alternating legs", "As a whole controller it falls. As corrections mid-stance follows; the leg pair moves as negatives of each other (gain about 1.0), the arms do not."],
            ["One toe-off keyframe too many", "Drop the one at 30% of the stride, keep toe-off: the keyframe-chunk runner falls on 1 of 48 starts instead of 6."],
            ["A 95th-percentile body", "Done, and a v4 body calibrated to human data."],
            ["Running motion-capture data", "Fukuchi 2017 treadmill running, in the trial run_natural_mocap."],
            ["Bolt's mechanics from blocks", "Keyframes built and used. The runner takes 6.72 s to 30 m against Bolt's 3.78 s."],
            ["A drag-the-joints keyframe editor", 'Done: <a href="https://claude.ai/artifact/HvFRzvSmo8esj7A2ELnxng">Keyframe Bench</a>.'],
            ["Demos on yaks.app", "thecompanygardener.yaks.app/robolab, last refreshed 27 Sep. The videos above are newer."],
        ], wide=True)
    requests = requests.replace("&lt;a href=&quot;https://claude.ai/artifact/HvFRzvSmo8esj7A2ELnxng&quot;&gt;Keyframe Bench&lt;/a&gt;",
                                '<a href="https://claude.ai/artifact/HvFRzvSmo8esj7A2ELnxng">Keyframe Bench</a>')

    search = table(
        ["Question", "Answer"],
        [
            ["Genetic algorithm?", "No. GA, differential evolution, cross-entropy, MAP-Elites, Nelder-Mead and random search all failed to improve on the jump."],
            ["Random walk?", "Yes for ballistic moves: the (1+1) random walk had the best median jump and the most robust run refinement, but it overfits badly when trained on fresh random perturbations."],
            ["Best for choreographed motion", "Bayesian optimisation or the random walk over goal posture + duration: 0.71 m median jump vs 0.13 m with rate vectors."],
            ["Best for robust balance", "Separable CMA-ES, trained on 4+ perturbations (falls on unseen pushes 12/30 to 3/30)."],
            ["Contraction vectors", "Never search raw per-muscle values; synergies distilled from good solutions converge fastest."],
            ["Keyframes, your idea", "It won. Converting the best posture solution into contraction keyframes and refining them in muscle space took the jump from 0.91 m to 1.3 to 1.5 m."],
            ["Since then", "Quintic knots with velocity and acceleration vectors, a small learned correction from proprioception (legal jump 1.27 to 1.33 m with no fall on any arena start), and a gait stride as a knot train fitted by least squares then improved by learning control."],
        ], wide=True)
    hood = (
        '<div class="cols">'
        '<div class="model"><h3>Bodies and arena</h3><ul class="list">'
        '<li>v2 anatomy: toe joints, biarticular muscles on fixed tendons, human peak joint speeds (elbow 35, knee 25, hip 15 rad/s), human-scale joint damping. Opt-in, so older results reproduce exactly.</li>'
        '<li>v3 adds elastic Achilles and quadriceps tendons; population bodies (average, 95th percentile, elite) and the calibrated v4 body are listed above.</li>'
        f'<li>The arena holds {n_trials} trials on fixed starts. A challenger replaces the champion on a paired sign-flip test (p &lt; 0.05), or on any strict gain in a one-start trial, and every result keeps the note of the approach that produced it.</li>'
        '</ul></div>'
        '<div class="model"><h3>SDK and compiler</h3><ul class="list">'
        '<li>Chunk spring times, joint corrections at limits and a dead tuning parameter were fixed in the SDK; <span class="mono">branch</span>, <span class="mono">followed_by</span>, <span class="mono">stagger</span> and <span class="mono">via</span> keyframes were added.</li>'
        '<li>Internal-model gravity feed-forward, a clamped reflex integral (postural tone), exact posture-to-contraction geometry for coupled joints and optional articulated fingers.</li>'
        '<li>Knot trains (<span class="mono">RunKnotsSkill</span>): a stride as quintic knots at its gait events, fitted with zero rollouts to 0.1 to 0.6° and 20 to 90 times better than min-jerk keyframes at the same events.</li>'
        '<li>Two compiler fixes are merged into main: methods with more than 8 parameters, and parameters named t0 or t1 colliding with LLVM temporaries (which also fixed a use-after-free).</li>'
        '</ul></div></div>')

    # ------------------------------------------------------------ assemble -----------
    def section(eyebrow, title, intro, *blocks):
        t = f"<h2>{e(title)}</h2>" if title else ""
        i = f"<p>{md(intro)}</p>" if intro else ""
        return f'<section><div class="eyebrow">{e(eyebrow)}</div>{t}{i}{"".join(blocks)}</section>'

    page = f'''<title>Robolab and pmndrs Progress</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Semi+Condensed:wght@500;600;700&family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>{CSS}</style>
<div class="wrap">
  <header class="head">
    <div class="eyebrow">Progress · updated {UPDATED}</div>
    <h1>Robolab, ability by ability</h1>
    <p class="lede">Each ability below shows its current champion, its newest video and where it stands against people or the challenge winner. Scores come from the champion-versus-challenger arena: {n_trials} trials ({n_champs} with a champion) on fixed starts. A challenger takes over on a paired sign-flip test (p < 0.05) where a trial has several starts, and on any strict gain where it has one. Numbers that come from an agent's own validation runs rather than an arena trial say so, and results marked provisional, ceiling study or Codex are labelled where they appear.</p>
    <div class="board" aria-label="Abilities">{board}</div>
  </header>

  {section("Your goals · 27 Sep", "Where each goal stands", "", goals)}

  {section("Against people", "How far each ability is from its reference", "Solid bars are robolab's best. Outlines are the ceiling with perfect control or an open-loop ceiling study. Grey bars are people or challenge winners. Hover or focus a row for its note, or switch a chart to its table.", charts)}

  {section("Running and sprinting", "", "", "".join(run_cards))}
  {section("Jumping and hurdles", "", "", "".join(jump_cards))}
  {section("Ball skills", "", "", "".join(ball_cards))}
  {section("Balance and soccer · MyoChallenge 2025 body, 290 muscles", "", "", "".join(soccer_cards))}
  {section("MyoChallenge arm and leg tasks", "", "Same control plane on the official MyoSuite bodies and scoring.", '<div class="cols">' + "".join(myo_cards) + "</div>")}

  {section("Bodies", "The bodies the results run on", "Each card names its body. Bodies are opt-in, and the older ones reproduce exactly.", bodies)}
  {section("Independent challengers · Codex", "A second team's results", "Codex runs its own matched-budget challenger campaign in a separate worktree. The middle column is its own report; the right column is what this arena did with it.", codex)}
  {section("Working now", "What is running", "The Codex jump and crossover champions ran here on 29 Sep and were promoted (see the Codex table), robolab is on main, and the compiler fixes are merged. Table tennis and the three campaign agents are still running.", working)}
  {section("Your requests", "Every request and where it stands", "", requests)}
  {section("Search methods · finished", "Genetic, random walk, or something else?", "Thirteen optimizers behind one interface, equal rollout budgets, several seeds and held-out re-checks, on a jump, push-recovery balance on the 80-muscle leg, and refining the run.", search)}
  {section("Under the hood", "", "", hood)}
  {section("pmndrs/math study · finished", "What Tungsten's core should borrow", "Biggest measured wins, in instructions per call: Vec3 length 43–47×, Quaternion slerp 23–31×, typed seeded RNG 18–21× (and it stops a 1 KB-per-draw leak), Quaternion rotate 14×, Mat4 transform_point 11×, compose 9.6×. A particle simulation runs 1.7× faster unchanged and 5.5× with in-place methods. Full tables are in `benchmarks/pmndrs_math/RESULTS.md`.")}
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


# Publish limit: 64 MB per call, so the videos go up in two batches (the page reloads with each).
BATCH_A = ["codex_jump_robust_r7.mp4", "run_knots.mp4", "sprint_p95_ri.mp4", "sprint_blocks.mp4", "sprint_touch.mp4", "long_jump_v6_p95.mp4",
           "codex_standing_jump.mp4", "hurdle_hs_076.mp4", "bat_v6_knots.mp4", "bat_v6.mp4", "dribble_btl.mp4",
           "codex_crossover.mp4"]


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
    if "--batches" in sys.argv:
        a = {k: files[k] for k in BATCH_A if k in files}
        b = {k: v for k, v in files.items() if k not in a}
        for label, batch in (("A", a), ("B", b)):
            size = sum(os.path.getsize(os.path.join(ROOT, v)) for v in batch.values())
            print(f"batch {label}: {len(batch)} files, {size / 1e6:.1f} MB", file=sys.stderr)
            print(json.dumps(batch, indent=0))


if __name__ == "__main__":
    main()
