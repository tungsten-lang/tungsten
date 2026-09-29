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
CODEX = "/Users/erik/.codex/worktrees/robolab-challengers/tungsten/bits/tungsten-robolab/results-page/dist/assets/"

UPDATED = time.strftime("%-d %b %Y, %-I:%M %p").replace("AM", "am").replace("PM", "pm")


def F(trial):
    """A champion's mean over the rollouts that passed their guards, as `arena.py board` prints it.

    Failed guards and crashes score +-1e9, which is why summary.mean alone is not the metric.
    """
    ok = [x for x in CHAMPS[trial].get("scores", []) if abs(x) < 1e8]
    return sum(ok) / len(ok) if ok else float("nan")


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
    "scored": ("done", "Scored"),
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


def chart(cid, title, unit, axis_max, ticks, rows, note, target=None):
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
        shown = r.get("shown") or (f'<b>{num(v)}</b> of {num(c)}' if c else f'<b>{num(v)}</b>')
        marks = ""
        if k == "ours":
            if c:
                marks += f'<span class="ctrack" style="width:{pct(c):.2f}%"></span>'
            marks += f'<span class="cbar" style="width:{pct(v):.2f}%"></span>'
        elif k == "study":
            marks += f'<span class="ctrack study" style="width:{pct(v):.2f}%"></span>'
        else:
            marks += f'<span class="cbar ref" style="width:{pct(v):.2f}%"></span>'
        tip_v = f'{num(v)} {unit}' + (f' (ceiling {num(c)})' if c else "")
        lines.append(
            f'<div class="crow" tabindex="0" data-l="{e(r["label"])}" data-v="{e(tip_v)}" data-n="{e(r.get("tip", ""))}">'
            f'<div class="clabel">{e(r["label"])}<small>{e(r.get("sub", ""))}</small></div>'
            f'<div class="cplot">{grid}{tgt}{marks}<span class="cval" style="left:calc({pct(end):.2f}% + 8px)">{shown}</span></div></div>')
        kind_txt = {"ours": "robolab", "study": "ceiling study", "ref": "people / winners"}[k]
        trs.append(f'<tr><td>{e(r["label"])}<br><small>{e(r.get("sub", ""))}</small></td><td class="n">{num(v)} {e(unit)}</td>'
                   f'<td class="n">{(num(c) + " " + e(unit)) if c else "–"}</td><td>{kind_txt}</td><td>{e(r.get("tip", ""))}</td></tr>')
    legend = []
    if "ours" in used:
        legend.append('<span><i class="sw ours"></i>Robolab best</span>')
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
def card(cid, title, chips, media, paras, tbl=None, nxt=None):
    ch = " ".join(chips)
    body = "".join(f"<p>{md(p)}</p>" for p in paras)
    nx = f'<p class="next"><b>Next.</b> {md(nxt)}</p>' if nxt else ""
    return f'''<article class="skill" id="{cid}">
  <div class="mediacol">{"".join(media)}</div>
  <div class="side"><h3>{e(title)}</h3><div class="chips">{ch}</div>{body}{tbl or ""}{nx}</div>
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

    n_trials = len(CHAMPS)

    # ------------------------------------------------------------ board -------------
    board_items = [
        ("run-natural", "Natural running", "done", "7.3° from human running, 12 starts"),
        ("sprint", "Sprint", "run", f"{V('sprint_top_speed_p95')} m/s, 95th pct."),
        ("blocks", "Sprint from blocks", "done", f"30 m in {V('sprint_blocks_30')} s · Bolt 3.78"),
        ("longjump", "Long jump", "run", f"4.90 m best · {V('long_jump_p95_robust')} m robust"),
        ("standing", "Standing jump", "done", f"{V('search_jump_legal', 3)} m legal"),
        ("hurdles", "Hurdles", "stuck", "0.762 m: 4 of 8 clear hurdle 1"),
        ("bat", "Baseball swing", "run", "21 m/s with reflexes on"),
        ("dribble", "Dribble", "run", "streak of 3 through the legs on 1–2 of 32 starts"),
        ("tt", "Table tennis", "stuck", f"P2 {100 * F('tt_p2_300'):.0f}% · P1 100%"),
        ("balance", "One-leg balance", "run", "12 of 20 hold 5 minutes"),
        ("soccer", "Penalty kick", "stuck", "P1 100% · P2 0%"),
        ("relocate", "Relocate", "scored", f"{V('relocate_p2eval_official', 3)} on the eval env"),
        ("chase", "Chase tag", "scored", f"{V('chase_p1', 3)} (winner 0.666)"),
        ("walk", "Walking", "scored", f"{V('walk_stride', 2)} m steps"),
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
             "21 m/s on 24 unseen pitches with reflexes on (was 13.8). 25.2 m/s as an open-loop ceiling study.",
             "MLB average about 32 m/s",
             "The reflex-on swing reaches 82–85% of the ceiling swing. Trunk and arms turn at 50–65% of MLB rates."],
            ["Dribble through the legs",
             "A streak of 3 through-the-legs passes on 1 to 2 of 32 fresh starts (mean longest streak 1.28 in 15 s). On 24 fresh 8 s runs the first pass is complete on 92% and the return on 42%.",
             "Target: several in a row",
             "The receiving hand cannot stop a fast, low ball and send it back up; arms lag the plan by 5–10 cm."],
            ["Exceed 10 m/s in the sprint",
             f"{V('sprint_top_speed_p95')} m/s (95th-percentile body). The first runner on the calibrated v4 body (average) is entered at {V('sprint_top_speed_v4')} m/s.",
             "Ceiling with perfect control on v4: 10.45 (95th pct.). Untrained men 7.8, trained sprinters 9.9.",
             "Only the average body has a v4 runner so far. 10 m/s needs 96% of the 95th-percentile v4 ceiling."],
            ["Long jump with the best runner, then beyond human",
             f"4.90 m on the 95th-percentile body (one start). Robust means: {V('long_jump_p95_robust')} m (95th pct.), {V('long_jump_elite2_robust')} m (elite), {V('long_jump_robust')} m (average).",
             "Untrained men 4.95 m, high school 6.07–6.65 m, world record 8.95 m",
             "In the landing search, 3 of 30 captured take-offs still roll over while the other 27 land at 4.6 to 4.95 m. With the 7.0 m/s runner the ideal take-off ceiling is 4.93 m, so passing 4.95 needs a faster runner."],
            ["Table tennis phase 2 above 90%",
             f"{100 * F('tt_p2_300'):.0f}% over 300 serves ({100 * F('tt_p2'):.0f}% over 100)",
             "Winner 64%, 80.3% after the challenge",
             "The paddle face follows 53 to 66% of an aimed change on the forehand and 13 to 28% on the backhand. Live arm tracking fixed the reach, but the tracked arm plays like a new player and needs a long practice run."],
            ["Balance five minutes on one leg",
             "12 of 20 fresh stances hold at least 300 s (strict 310 s trial). A version with a tuned lift holds 15 of 20, not yet significant.",
             "Target: 300 s",
             "Every failure happens at the lift into single support."],
            ["Score all the soccer goals",
             "Phase 1 100%. Phase 2 0 of 100.",
             "2023 winner 32% on phase 2",
             "The kick fails from a settled stance, and this body cannot walk upright: its spine folds."],
            ["Improve robolab",
             f"{n_trials} arena trials, a calibrated v4 body, a MyoSuite relocate bug found, two compiler fixes waiting for review.",
             "–",
             "See what is running and what waits for you, near the end."],
        ], wide=True)

    # ------------------------------------------------------------ charts ------------
    ch_sprint = chart(
        "c-sprint", "Sprint speed", "m/s", 15, [0, 3, 6, 9, 12],
        [
            dict(label="Average body", sub="best on the v3 body", value=F("sprint_top_speed"), ceiling=8.2, kind="ours",
                 tip="Ceiling with perfect control and a free torso: 6.89 on the v3 body, 8.2 on v4. A first v4 runner is entered at 4.65."),
            dict(label="95th percentile", sub="best on the v3 body", value=F("sprint_top_speed_p95"), ceiling=10.45, kind="ours",
                 tip="Ceiling with perfect control and a free torso: 9.69 on the v3 body, 10.45 on v4."),
            dict(label="Elite, literature", sub="best on the v3 body", value=F("sprint_top_speed_elite2"), ceiling=9.28, kind="ours",
                 tip="Ceiling: 8.5 on the v3 body, 9.28 on v4. Every part of this profile is cited; its knee and ankle extensors sit near the untrained mean."),
            dict(label="Untrained men", sub="reference", value=7.8, kind="ref", tip="7.3–8.3 m/s (Lazarczuk 2025; Clark et al. 2020)"),
            dict(label="Trained sprinters", sub="reference", value=9.9, kind="ref", tip="9.90 ± 0.46 m/s (Miyashiro et al. 2019)"),
            dict(label="Elite sprinters", sub="reference", value=11.8, kind="ref", tip="11.5–12.3 m/s; 2009 finalists 11.80 (Bolt 12.26)"),
        ],
        "Bars are the arena champions on the v3 bodies. Outlines are the ideal-control ceiling with the torso free on the calibrated v4 body (the v3 ceilings are in each row's note). An earlier 10.2 m/s ceiling rested on an ideal torso stabiliser and is not used.",
        target=dict(v=10, label="Goal 10 m/s"))

    ch_jump = chart(
        "c-jump", "Long jump", "m", 10, [0, 2, 4, 6, 8, 10],
        [
            dict(label="Average body", sub="16 perturbed starts", value=F("long_jump_robust"), kind="ours", tip="One-start best 2.47 m."),
            dict(label="95th percentile", sub="16 perturbed starts", value=F("long_jump_p95_robust"), ceiling=4.93, kind="ours",
                 tip="One-start champion 4.895 m. Ceiling 4.93 m is the ideal take-off from this runner's own approach (7.0 m/s)."),
            dict(label="Elite, literature", sub="16 perturbed starts", value=F("long_jump_elite2_robust"), ceiling=4.25, kind="ours",
                 tip="One-start champion 4.01 m. Ceiling 4.25 m from its 6.6 m/s approach."),
            dict(label="Elite, old profile", sub="provisional", value=F("long_jump_elite_robust"), kind="ours",
                 tip="Uses the elite profile whose muscle strengths were set too high; treat as provisional."),
            dict(label="Untrained women", sub="reference", value=3.57, kind="ref", tip="3.57 ± 0.54 m (Romdhani et al. 2026)"),
            dict(label="Untrained men", sub="reference", value=4.95, kind="ref", tip="4.95 ± 0.55 m (Romdhani et al. 2026)"),
            dict(label="High-school qualifying", sub="reference", value=6.36, kind="ref", tip="Boys 6.07–6.65 m (Oregon 2026 standards); run-up 8.9 m/s"),
            dict(label="College finals", sub="reference", value=7.66, kind="ref", tip="NCAA D1 finals medians 7.56–7.75 m"),
            dict(label="World record", sub="reference", value=8.95, kind="ref", tip="Powell 1991; run-up 11.0 m/s"),
        ],
        "Bars are robust means on the 16 arena starts. Outlines are the ideal-control ceiling for each runner's own approach.")

    ch_bat = chart(
        "c-bat", "Bat speed at contact", "m/s", 40, [0, 10, 20, 30],
        [
            dict(label="Hitch-free swing", sub="before (v5)", value=13.86, kind="ours", tip="24 pitches it never saw. The swing had a plan-limited arm drive."),
            dict(label="Codex pure search", sub="independent", value=14.79, kind="ours", tip="Keeps the pause before and after contact."),
            dict(label="Reflexes on", sub="latest (knots)", value=21.57, kind="ours",
                 tip="Contraction knots distilled from the fast swing, reflexes on. 2–4 misses in 24; the other variant scored 20.63."),
            dict(label="Open-loop program", sub="ceiling study", value=25.24, kind="study",
                 tip="Excitation program, reflexes off. 24 of 24 hits. Optimised on 6 of the 18 grid pitch locations, scored on 24 new pitches."),
            dict(label="MLB average", sub="reference", value=32.0, kind="ref", tip="About 72 mph at the sweet spot"),
        ],
        "All robolab bars are scored on 24 pitches that no swing was trained on (the fresh-pitch trial).")

    ch_tt = chart(
        "c-tt", "Table tennis, phase 2", "%", 100, [0, 25, 50, 75, 100],
        [
            dict(label="Robolab, all serves", sub="300 serves", value=round(100 * F("tt_p2_300"), 1), kind="ours",
                 tip="Forehand serves 36–46%, backhand serves 23%."),
            dict(label="Robolab, backhand serves", sub="131 serves", value=round(100 * F("tt_p2_backhand"), 1), kind="ours",
                 tip="The backhand works, but weakly."),
            dict(label="Challenge winner", sub="reference", value=64, kind="ref", tip="2025 MyoChallenge phase 2"),
            dict(label="Best after the challenge", sub="reference", value=80.3, kind="ref", tip="Post-challenge result on the same task"),
        ],
        "MyoChallenge phase-2 success rate: the share of serves the task scores as solved.",
        target=dict(v=90, label="Goal 90%"))

    charts = f'<div class="chartgrid">{ch_sprint}{ch_jump}{ch_bat}{ch_tt}</div>'

    # ------------------------------------------------------------ ability cards -----
    run_cards = [
        card("run-natural", "Natural running from human keyframes", [chip("done")],
             [vid("run_knots.mp4", out("run_knots.mp4"), "Natural runner with the literature curves ghosted",
                  "12 s of the current runner. The literature gait curves are ghosted at the current stride phase.")],
             ["Contraction keyframes at touchdown, mid-stance and toe-off from human running data, eased through and latched on the feet. The latest version adds a knot at each gait event (a contraction, a velocity and an acceleration for every muscle), fitted to the target by least squares and then improved from stride-by-stride error curves (iterative learning control).",
              "Against the literature curves it is now **7.3°** from human running on the 12-start trial, down from 9.1° and better on every start that stayed up. On the harder 48-start trial it is 7.2° with 13 falls against 17, which is not significant. Against motion-capture running (Fukuchi 2017) it is 10.1° and falls on 11 of 48 fresh starts where the earlier runner fell on 17. Against your keyframe set 3, dropping the heel-rise keyframe at 30% of the stride cut the falls from 9 to 1 in 48 starts, with the pose 2.2° further from your set."],
             table(["Target (fresh starts, paired p)", "Before", "Now"],
                   [["Literature curves (12, p 0.0005)", "#1 fall, 9.13°", "#1 fall, 7.29°"],
                    ["Literature curves, harder trial (48, p 0.17, not promoted)", "#17 falls, 9.22°", "#13 falls, 7.22°"],
                    ["Motion capture (48, p 0.0498)", "#17 falls, 11.0°", "#11 falls, 10.09°"],
                    ["Your set 3, heel-rise keyframe dropped (48, p 0.0095)", "#9 falls, 17.56°", "#1 fall, 19.78°"]]),
             "Train the small learned correction (a convolutional network on proprioception) for the literature and set-3 runners, where the knots alone fall on 8 and 7 of 48 held-out starts. On the mocap runner it cut held-out falls from 14 to 4 in 48."),
        card("sprint", "Sprint", [chip("run"), chip("study", "v4 body: first runner in")],
             [vid("sprint_p95_ri.mp4", out("sprint_p95_ri.mp4"), "Sprinter on the 95th-percentile body, 7 m/s",
                  "The champion on the 95th-percentile body from a standing start.")],
             [f"Full drive on the prime movers with the opposing muscles switched off (reciprocal inhibition), latched on each foot. **{V('sprint_top_speed_p95')} m/s** on the 95th-percentile body, {V('sprint_top_speed_elite2')} on the literature elite body, {V('sprint_top_speed')} on the average body. Switching the opposing muscles off is worth +0.12 m/s on every start, and without it the gait falls within 5 seconds.",
              "An earlier ceiling of about 10.2 m/s for the 95th-percentile body rested on an ideal torso stabiliser that applies up to 3.9 kN·m in a 0.12 s stance, where the stance hip's muscles give at most 185 N·m. Ceilings are now computed with the torso free. On the original body that put the average runner's ceiling at 6.89 m/s, below untrained men's 7.8, so the body model was calibrated against published data (the v4 body, below). On v4 the ceilings are 8.2, 10.45 and 9.28 m/s.",
              f"The first v4 runner (average body) is entered at **{V('sprint_top_speed_v4')} m/s** on {passes('sprint_top_speed_v4')} arena starts, {100 * F('sprint_top_speed_v4') / 8.2:.0f}% of its ceiling. It lands on a nearly straight leg, and on some starts it settles into a slower gait."],
             table(["Body", "Best on v3", "v3 ceiling", "v4 runner", "v4 ceiling"],
                   [["Average", f"#{V('sprint_top_speed')}", "#6.89", f"#{V('sprint_top_speed_v4')}", "#8.2"],
                    ["95th percentile", f"#{V('sprint_top_speed_p95')}", "#9.69", "#–", "#10.45"],
                    ["Elite, literature", f"#{V('sprint_top_speed_elite2')}", "#8.5", "#–", "#9.28"]]),
             "Move the v4 runner's stance toward the ideal one, then enter the 95th-percentile and elite bodies. 10 m/s on v4 needs 96% of the 95th-percentile ceiling."),
        card("blocks", "Sprint from blocks, keyframed on Usain Bolt", [chip("done", "Champion"), chip("study", "About 2x Bolt's time")],
             [vid("sprint_blocks.mp4", out("sprint_blocks.mp4"), "Start from blocks with Bolt's pose ghosted",
                  "Bolt's pose is ghosted over the runner. No broadcast frames are shown.")],
             ["Keyframes measured from side-view footage of Bolt: block exit, the first steps and the max-velocity cycle. The set position is the mean of the 2018 World Indoor 60 m finalists, and steps 3 to 10 are interpolated. The runner sets on two angled pads, pushes off the rear pad on its force, then the front pad, then accelerates through steps blended from Bolt's first steps into his max-velocity cycle. Reaction time is 0.237 s.",
              f"On the 95th-percentile body it covers 30 m in **{V('sprint_blocks_30')} s** and 100 m in **{V('sprint_blocks_100')} s** on 11 of 12 arena starts. Bolt ran 3.78 s and 9.58 s, so this is about twice his time and 4 to 6 s behind a recreational sprinter: 3.3 steps a second of 1.7 m against his 4.5 of 2.4 to 2.7 m. The same controller on the average body falls on every start. At touchdown its trunk leans about 30° more than Bolt's upright 4°."],
             None,
             "Reuse this start for the hurdler, and move it to the v4 body once a v4 sprinter exists."),
        card("touch", "Touch-only sprint", [chip("done")],
             [vid("sprint_touch.mp4", out("sprint_touch.mp4"), "Sprint from a single touchdown keyframe", "Muscles are tinted by activation.")],
             ["Your idea of keyframing only the toe-touch. One right-touchdown keyframe (the left is its mirror), each stride one spline from touch to touch, with the joint velocities at the touch, and full-power bursts timed on each leg's own touchdown and toe-off. Without the velocities every version fell within two steps.",
              "It took over the fast-running trial: 10 of 12 starts stay up where the old champion failed all 12. The quadriceps pulse at landing alone is worth 0.7 m/s. It runs 4.6 m/s on the average body against 5.0 for the tuned sprinter."],
             None, None),
    ]

    jump_cards = [
        card("longjump", "Long jump", [chip("run")],
             [vid("long_jump_v5_p95.mp4", out("long_jump_v5_p95.mp4"), "Long jump on the 95th-percentile body, 4.9 m",
                  "The one-start champion on the 95th-percentile body: 4.895 m. The take-off, flight and landing play at quarter speed.")],
             ["The run-up is the sprint champion itself. World Athletics rules are in the score: foul line on every tick of the stance, no somersault past 120°, no touching the runway after landing, and the mark is the nearest break in the sand by any body part. The take-off comes from an ideal-control analysis of the runner's own approach, distilled into contraction knots latched on the plant touchdown.",
              f"That took the 95th-percentile body from 3.68 to **4.895 m** on one start (99% of its 4.93 m ceiling) and from 3.22 to **{V('long_jump_p95_robust')} m** on 16 perturbed starts. The average body reaches {V('long_jump_robust')} m robust and 2.47 m on one start."],
             table(["Body", "One start", "16 starts", "Ceiling"],
                   [["Average", "#2.47", f"#{V('long_jump_robust')}", "#–"],
                    ["95th percentile", f"#{V('long_jump_p95', 3)}", f"#{V('long_jump_p95_robust')}", "#4.93"],
                    ["Elite, literature", f"#{V('long_jump_elite2')}", f"#{V('long_jump_elite2_robust')}", "#4.25"],
                    ["Elite, old profile (provisional)", f"#{V('long_jump_elite')}", f"#{V('long_jump_elite_robust')}", "#–"]]),
             "Find why 3 of 30 captured take-offs still roll over on landing. Then build the same jump on the v4 sprinter, which is the only way to pass the untrained man's 4.95 m."),
        card("standing", "Standing broad jump", [chip("done"), chip("study", "Codex policy")],
             [vid("codex_standing_jump.mp4", CODEX + "competitor_jump_round2__video_search_jump_legal_tcn.mp4", "Standing jump champion, 1.363 m",
                  "Codex's champion for the legal-distance trial: it lands and stays on its feet.")],
             [f"Contraction keyframes with take-off and landing latched on the centre of mass. The legal-distance champion is Codex's temporal recovery policy at **{V('search_jump_legal', 3)} m** (8 starts): a small learned correction after landing that keeps the jumper on its feet. On 32 larger nudges the champion is our convolutional keyframe policy: **{V('search_jump_robust_legal', 3)} m** with 32 of 32 landing.",
              "Codex reports a newer robustness champion of 1.3397 m in its own worktree. It has not been run in this arena yet."],
             None, None),
        card("hurdles", "Hurdles", [chip("stuck", "Waiting on run-up")],
             [vid("hurdle_hs_076.mp4", out("hurdle_hs_076.mp4"), "Hurdler at 0.762 m", "Hurdle height 0.762 m (2 ft 6 in).")],
             ["Lead knee driven up and extended over the bar, the trail leg lifted out to the side and turned so the knee comes around. At 0.762 m it clears the first hurdle on 4 of 8 starts and then falls. At your high-school height of 0.991 m the lead leg clears and the trail leg catches.",
              "The run-up is the limit: about 4 m/s at the first hurdle where a high-school hurdler arrives near 7. The start from blocks reaches 5.0 m/s at 13.7 m, on the 95th-percentile body."],
             None, "Rebuild the approach on the blocks start and, later, the v4 sprinter; then work the trail leg."),
    ]

    ball_cards = [
        card("bat", "Baseball swing", [chip("run"), chip("study", "Ceiling study shown")],
             [vid("bat_v6_knots.mp4", out("bat_v6_knots.mp4"), "Swing with contraction knots and reflexes on",
                  "In robolab's representation (contraction knots, reflexes on): 21 m/s on pitches it never trained on."),
              vid("bat_v6.mp4", out("bat_v6.mp4"), "Open-loop ceiling swing",
                  "Ceiling study: an open-loop excitation program with the reflexes off, 25 m/s.")],
             ["The earlier hitch-free swing was slow because of its plan. The arms and wrists fired at full power only 2–8% of the swing, the bottom wrist uncocked early, and the bat peaked 42 ms before contact. The fast swing turns the pelvis at full drive into its yaw limit, keeps the spine coiled, fires short arm bursts with no co-contraction, and whips the bottom wrist through 0.8 rad in the last 60 ms. The wrist runs at 1,070 °/s, the same as college hitters (1,093).",
              "The open-loop program scores 25.2 m/s on 24 pitches it never saw and hits all 24, so it is not tuned to the 18 test pitches. Distilled into contraction knots with the reflexes on, it keeps 82–85% of that speed. Trunk and arms turn at only 50–65% of MLB rates. Landing the step 62 ms later cut the pause before the swing from 115 ms to 50 ms."],
             table(["Swing", "18 test pitches", "24 new pitches"],
                   [["Hitch-free (before)", "#13.78", "#13.86"],
                    ["Codex pure search", "#14.72", "#14.79"],
                    ["Reflexes on, knots", "#23.1–24.5", "#20.6–21.6"],
                    ["Open-loop program (ceiling study)", "#25.17", "#25.24"]]),
             "Train the knots directly on fresh continuous pitches, add more programs to blend, and shorten the pre-swing pause."),
        card("dribble", "Dribbling", [chip("run")],
             [vid("dribble_btl.mp4", out("dribble_btl.mp4"), "Three passes through the legs in a row",
                  "Through the legs: three passes in a row on a start the search never saw, with a slow-motion replay of the pass."),
              vid("codex_crossover.mp4", CODEX + "competitor_20260927__video_dribble_crossover_25_tcn.mp4", "Crossover dribble, Codex champion",
                  "Crossovers: Codex's champion, 7.52 per 15 s run. The ball is eventually lost on every run.")],
             ["**Through the legs.** A stance planner picked a staggered lunge with the trunk twisted toward the lead leg, and catch spots that both hands can reach from behind the ball. On 24 fresh 8 s runs the first pass is complete on 22 (92%), the return on 10 (42%), and 33 of 61 passes are good (54%). A streak of 3 shows up on only 1 or 2 of 32 fresh starts. The earlier \"between the legs\" video was a low crossover in front of the lead foot: the ball never went through the gap, and the arena's leg-gate count for it is 0 on all 25 starts.",
              "**Crossovers.** Codex's small learned correction from the recent ball motion doubled the count to 7.52 per run. The trunk still pumps and the hands are still paddles."],
             table(["Trial", "Champion", "Was"],
                   [["Through the legs, 25 starts (good passes per attempt, at least 10)", f"#{V('dribble_btl_25', 3)}", "#0.000"],
                    ["Through the legs, longest streak (mean)", f"#{V('dribble_btl_streak_25', 2)}", "#–"],
                    ["Crossovers per run, 25 starts", f"#{V('dribble_crossover_25')}", "#3.72"]]),
             "A streak of 5 needs a receiving hand that catches a fast low ball, so try catching it while it is still rising, closer catch spots, and a turn of the trunk into the catch."),
        card("tt", "Table tennis", [chip("stuck")],
             [vid("myo_tt_r5.mp4", out("myo_tt_r5.mp4"), "Five consecutive returns", "Five consecutive returns by the phase-2 champion."),
              vid("myo_tt_strokes.mp4", out("myo_tt_strokes.mp4"), "Chop, wrist flick and low scoop",
                  "Chop, backhand flick and low forehand scoop with real ball spin, at the best angles found.")],
             ["Predicts the ball through the bounce, slides the pelvis onto its path, latches the ready posture on time-to-paddle and sets the paddle face from an aim law. Phase 1 is 100%. Phase 2 is **33%** over 300 serves, and the winner scored 64%.",
              "The aim is accurate. The arm does not carry it out: a forehand asked to turn its forearm 1.20 rad reaches 0.44, and the face follows 0.53 to 0.66 of an aimed change on the forehand and 0.13 to 0.28 on the backhand (1 would be perfect). Live moment arms fix the arm's tracking (backhand error 0.80 to 0.21 rad, forehand yaw follow 0.66 to 1.01), but the tracked arm plays like a new player and needs a long practice run. Where the ball meets the paddle decides most forehands: 67% solved within 3 cm of the centre, 1 in 7 on the rim.",
              "Your strokes: the chop goes high because the aim rule opens the forehand face about 40° and the forehand path cannot get steeper than about 40° down. The best chop is the backhand, commanded at a 60° face and a 40° downward path, which reaches −4° and 33° down (4 cm over the net, 11 rev/s of backspin, 3 of 11 landed). The wrist flick makes topspin, under 5 rev/s, because its paddle reaches only 1.3 to 1.5 m/s."],
             None,
             "A long practice run of the tracked arm on both sides, or a learned drive correction below the contraction layer. 90% is far above anything reached on this task."),
    ]

    soccer_cards = [
        card("balance", "One-leg balance", [chip("run")],
             [vid("soccer_balance_300.mp4", out("soccer_balance_300.mp4"), "Standing on one leg for the first 40 seconds of a 298 second hold",
                  "The first 40 s of a 298 s one-leg stance on the 290-muscle body.")],
             ["The hold is steered by the sensed centre of pressure, with a slow centring loop and per-posture muscle moment arms. The centring loop is what carries a hold past 96 s. On a 310 s trial, **12 of 20** fresh stances stay on one leg for at least 300 s, and a version with a tuned lift holds 15 of 20 (p 0.23 on 20 starts, not promoted). The short two-leg trial (3 s on each leg, at most 6) went from 1.96 to 3.08 s, with the right leg still the weak one (0.63 s).",
              "Round 4 overturned the first diagnosis: in single support the standing foot's heading stays within 0.02 rad, so it does not spin. What was wrong was the controller's hip model, measured at the start posture: the gluteal moment arms change sign where one-leg stance happens (one muscle's rotation torque per unit activation runs from −29 to +37 N·m). Every remaining failure is at the lift: the swing foot leaves the ground still carrying 20–40% of body weight, which throws the capture point 5–6 cm outward, past the ±2 cm the sole can absorb, and the standing foot then spins 0.3–0.4 rad."],
             None,
             "A 40-start version of the 310 s trial so a 15-of-20 result can be confirmed, then a better lift."),
        card("soccer", "Penalty kick", [chip("done", "Phase 1 champion"), chip("stuck", "Phase 2 blocked")],
             [vid("myo_soccer.mp4", out("myo_soccer.mp4"), "Penalty kick, phase 1", "Phase 1: 100% of 50 starts."),
              vid("soccer_p2_v4.mp4", out("soccer_p2_v4.mp4"), "Phase 2 attempt", "Phase 2 attempt: one step, then a fall.")],
             ["Shift weight, step, plant beside the ball, swing with a hip-flexor burst and knee snap latched on ball contact, aiming away from the keeper. Phase 1 scores every time. Phase 2 starts 0.02 to 1.4 m from that stance and lasts 10 s, and it scores 0 of 100 (the 2023 winner scored 32%).",
              "Two measured walls. The phase-1 kick is a trajectory from one exact start, and from a settled stance it scores 0 of 30 starts even within 0.3 m of the phase-1 stance. And this body cannot walk upright: the abdominal muscle's passive pull plus the upper body's weight need 84 to 123% of the back extensors' capacity whenever the chest is upright, so the chase-tag walker folds its spine within 0.5 s."],
             None,
             "Rebuild the kick in stages from the settled stance, then a faster approach."),
    ]

    myo_cards = [
        small("Relocate", [chip("scored")], vid("relocate_v6.mp4", out("relocate_v6.mp4"), "Relocate, round 6",
                                               "A 295 g object from the far left, carried and held inside the box."),
              f"Official score {V('relocate_p2eval_official', 3)} on the evaluation environment (was 0.210), genuine lifts {V('relocate_p2eval_lift', 3)}. On the easier phase-2 environment, lifts {V('relocate_p2_300', 3)}. MyoSuite 2.12.2 steps a second copy of the scene whose receptacle sits at the random target, invisible to the observation, while the visible box has no walls. Scores here are not comparable to the 2023 winner's 0.343."),
        small("Chase tag", [chip("scored")], vid("myo_chase_v2.mp4", out("myo_chase_v2.mp4"), "Chase tag", "Two leg tracks with turning."),
              f"Phase 1 {V('chase_p1', 3)} (winner 0.666), phase 2 {V('chase_p2', 2)}. Each leg loops stance, push, lift and reach on its own sensed events; a step-turn loop turns toward an opponent behind."),
        small("Walking on the myoLeg", [chip("scored")], vid("myo_walk_v2.mp4", out("myo_walk_v2.mp4"), "MyoLeg walking with the longer stride", "The 80-muscle leg model with the step-length champion: 0.46 m steps at 1.44 m/s, until it reaches the arena edge."),
              f"Step length {V('walk_stride', 2)} m (was 0.36, people about 0.7), at 1.2 to 1.5 m/s. The longer-stride gait trades pace control for step length. Quiet standing survives pushes of 60 to 80 N."),
        small("Baoding balls", [chip("scored")], vid("myo_baoding_v3.mp4", out("myo_baoding_v3.mp4"), "Baoding balls", "Palm tilt and roll tied to the ball angle."),
              f"Score {V('baoding_p2', 3)} against the winner's 0.55. It holds both balls and nudges them but never found a rolling gait."),
        small("Die reorientation", [chip("stuck")], vid("myo_die_v3.mp4", out("myo_die_v3.mp4"), "Die", "Finger flips plus palm tilt and roll."),
              f"Removes {V('die_p2_progress', 2)} rad of the die's rotation (was 0.19) with no full solves yet. The winner scores 0.13."),
        small("Bimanual handover", [chip("stuck")], vid("bimanual_v4.mp4", out("bimanual_v4.mp4"), "Bimanual handover", "The arm holds the box out steadily."),
              f"Staged progress {V('bimanual_stages', 2)} (was 0.33) with no full success. The prosthesis mostly presses its hand against the held box; it is not yet a grip."),
    ]

    # ------------------------------------------------------------ bodies -------------
    bodies = table(
        ["Body", "What it is", "Sprint ceiling, torso free", "Used for"],
        [
            ["Average (v2, v3)", "Average adult. v3 adds elastic Achilles and quadriceps tendons.", "6.89 m/s on v3", "All the older results"],
            ["95th percentile", "Strength ×1.32, muscle speed ×1.2 and tendon stiffness ×1.5 (each a 95th percentile of published data), activation time constants ×0.87 (inferred; no population distribution exists).", "9.69 m/s on v3", "Sprint, blocks, long jump"],
            ["Elite, old profile", "Strengths set per muscle from memory of the papers (hip extensors ×1.6, vasti ×1.3, speed ×1.3). A check on 28 Sep found iliopsoas, vasti, soleus, gastrocnemius, the quadriceps tendon and activation set too strong.", "unverified", "Results marked provisional"],
            ["Elite, literature (elite2)", "Every part cited. Elite knee and ankle extensors sit near the untrained mean.", "8.5 on v3, 9.28 on v4", "New trials"],
            ["v4, calibrated", "v3 with two literature-backed changes: quadriceps series stiffness 250 to 1000 N/mm, hip speeds 15 to 18.5 (extension) and 29 (flexion) rad/s.", "8.2 average, 10.45 95th pct., 9.28 elite2", "Sprinters being tuned now"],
        ], wide=True)

    # ------------------------------------------------------------ codex --------------
    codex = table(
        ["Result", "Codex reports", "In this arena"],
        [
            ["Standing jump, legal distance", "1.363 m (temporal recovery)", "Champion here (run 27 Sep)"],
            ["Crossovers, 25 starts", "7.52, later 9.08 (R9)", "7.52 is the champion here; 9.08 not yet run"],
            ["Standing jump, robustness (32 starts)", "1.3397 m, 32 of 32 (R7)", "Ours 1.3153. Not yet run here"],
            ["Bat power", "14.72 m/s, pause before and after contact kept", "Superseded by the reflex-on swing above"],
            ["Dribble rounds 10 and 11", "R10 no promotion. R11 (fingered hand) started, not finished", "–"],
        ], wide=True)

    # ------------------------------------------------------------ running now --------
    working = table(
        ["Workstream", "Where it stands", "Next"],
        [
            ["Sprint on the v4 body", f"Restarted 1 am 29 Sep. The average-body runner is entered at {V('sprint_top_speed_v4')} m/s; searches for a better stance and the 95th-percentile body are running.", "Then the elite body"],
            ["Long jump", "Restarted 1 am. The landing search had plateaued with 3 of 30 captured take-offs rolling over.", "Diagnose the roll-overs; a v4 family after a v4 sprinter"],
            ["Soccer balance and phase 2", "Restarted 1 am.", "A 40-start 310 s trial; the staged kick curriculum"],
            ["Dribble through the legs, bat speed, table tennis, runner, hurdles, relocate", "Written up in the handoff for Codex to pick up (bits/tungsten-robolab/HANDOFF_20260929.md)", "Codex chooses"],
        ], wide=True)
    waiting = table(
        ["Waiting for you", "Detail"],
        [
            ["Run Codex's newer champions here", "Jump robustness 1.3397 m and crossovers 9.08, the same way as the first three."],
            ["Land the robolab branch on main", "All robolab work is committed on branch robolab-campaign-2026-09 (about 1,700 files, 40 MB, nothing over 2 MB; the frozen binaries and videos stay out). Main is untouched."],
            ["Review two compiler fixes", "Methods with more than 8 parameters (branch worktree-agent-a2c3280fe1aeba8ae) and parameters named t0 or t1 colliding with LLVM temporaries, which also fixed a use-after-free (branch worktree-agent-aecbbb4851919b588)."],
            ["Report the MyoSuite relocate bug upstream", "Confirmed: the physics steps a second copy of the scene with an invisible receptacle."],
        ], wide=True)

    # ------------------------------------------------------------ requests -----------
    requests = table(
        ["You asked", "Where it stands"],
        [
            ["A natural runner: power leg extended, other knee and arm up", "Built and improved: 7.3° from human running (was 9.1°) on the 12-start trial."],
            ["Batter hitch, before and after contact", "After contact: fixed (the stall was the wrist and the pelvis hitting their joint limits). Before the swing: a 50 ms pause remains in the reflex-on swing."],
            ["Dribble: a visible crossover, less back, more elbow, fingers", "Crossover 7.52 per 15 s run. The trunk still pumps. The fingered hand is built (opt-in); Codex's fingered-hand search is running."],
            ["A better long-jump run and take-off", "4.9 m on one start; the sprinter is the run-up."],
            ["Hurdles at high-school height", "0.762 m: 4 of 8 clear hurdle 1. Waiting on run-up speed."],
            ["Table tennis backhand, wrist flick, chop, low scoop", "The backhand exists (23% of backhand serves solved). Chop, flick and scoop were measured with real ball spin: the best chop lands 3 of 11, the flick 0 of 20, the scoop 2 of 20."],
            ["Soccer kick with the inside of the foot", "Not yet: the best attempt strikes with the toes."],
            ["MyoLeg longer strides", f"{V('walk_stride', 2)} m (was 0.36; people about 0.7)."],
            ["Toe-touch and toe-off keyframes only, alternating legs", "As a whole controller it falls. As corrections mid-stance follows; the leg pair moves as negatives of each other (gain about 1.0), the arms do not."],
            ["One toe-off keyframe too many", "Drop the one at 30% of the stride, keep toe-off: 1 fall in 48 starts."],
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
        f'<li>The arena holds {n_trials} trials on fixed held-out starts. A challenger replaces the champion only when it wins a paired sign-flip test, and every result keeps the note of the approach that produced it.</li>'
        '</ul></div>'
        '<div class="model"><h3>SDK and compiler</h3><ul class="list">'
        '<li>Chunk spring times, joint corrections at limits and a dead tuning parameter were fixed in the SDK; <span class="mono">branch</span>, <span class="mono">followed_by</span>, <span class="mono">stagger</span> and <span class="mono">via</span> keyframes were added.</li>'
        '<li>Internal-model gravity feed-forward, a clamped reflex integral (postural tone), exact posture-to-contraction geometry for coupled joints and optional articulated fingers.</li>'
        '<li>Knot trains (<span class="mono">RunKnotsSkill</span>): a stride as quintic knots at its gait events, fitted with zero rollouts to 0.1 to 0.6° and 20 to 90 times better than min-jerk keyframes at the same events.</li>'
        '<li>Compiler fixes on branches for you to merge: methods with more than 8 parameters, and parameters named t0 or t1 colliding with LLVM temporaries (which also fixed a use-after-free).</li>'
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
    <p class="lede">Each ability below shows its current champion, its newest video and where it stands against people or the challenge winner. Every score comes from the champion-versus-challenger arena: {n_trials} trials, each on fixed held-out starts, and a challenger takes over only when it beats the champion on the same starts (a paired test where a trial has several starts). Results marked provisional or ceiling study are labelled where they appear.</p>
    <div class="board" aria-label="Abilities">{board}</div>
  </header>

  {section("Your goals · 27 Sep", "Where each goal stands", "", goals)}

  {section("Against people", "How far each ability is from its reference", "Solid bars are robolab's best. Outlines are the ceiling with perfect control or an open-loop ceiling study. Grey bars are people or challenge winners. Hover or focus a row for its note, or switch a chart to its table.", charts)}

  {section("Running and sprinting", "", "", "".join(run_cards))}
  {section("Jumping and hurdles", "", "", "".join(jump_cards))}
  {section("Ball skills", "", "", "".join(ball_cards))}
  {section("Balance and soccer · MyoChallenge 2025 body, 290 muscles", "", "", "".join(soccer_cards))}
  {section("MyoChallenge arm and leg tasks", "", "Same control plane on the official MyoSuite bodies and scoring.", '<div class="cols">' + "".join(myo_cards) + "</div>")}

  {section("Bodies", "The bodies the results run on", "Every result names its body. A body is opt-in, and the older ones reproduce exactly.", bodies)}
  {section("Independent challengers · Codex", "A second team's results", "Codex runs its own matched-budget challenger campaign in a separate worktree. This table is its own report. Only the first row was run here so far.", codex)}
  {section("Working now", "What is running and what waits for you", "", working, waiting)}
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
BATCH_A = ["run_knots.mp4", "sprint_p95_ri.mp4", "sprint_blocks.mp4", "sprint_touch.mp4", "long_jump_v5_p95.mp4",
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
