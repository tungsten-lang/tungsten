#!/usr/bin/env python3
"""Headless-Chrome preview of the progress page (agent P9, 3 Oct 2026).

    python3 scratchpad/progress29/preview.py PORT HTML TAG MARKER [desktop|phone|none] [id1,id2,...] [section height px]

Serves a preview dir on 127.0.0.1:PORT from a thread of this process (a port that is already taken raises, so a stale
server can never answer), proves that the served page contains MARKER, measures the page height at desktop width and in a
390 px iframe (also listing elements that stick out to the right of the iframe outside any scroll container), and writes
full-page screenshots for the light and the dark theme (`data-theme`) to scratchpad/progress29/shots/<TAG>_{desktop,phone}_{light,dark}.png.
Nothing keeps running after it exits.
"""
import functools
import http.server
import importlib.util
import json
import os
import re
import socketserver
import subprocess
import sys
import threading
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

port, html_path, tag, marker = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
only = sys.argv[5] if len(sys.argv) > 5 else ""
IDS = [x for x in (sys.argv[6].split(",") if len(sys.argv) > 6 else []) if x]     # phone screenshots of these element ids
SECH = int(sys.argv[7]) if len(sys.argv) > 7 else 2400

pdir = os.path.join(HERE, f"preview_{tag}")
shots = os.path.join(HERE, "shots")
os.makedirs(pdir, exist_ok=True)
os.makedirs(shots, exist_ok=True)

# the video files the page references, linked next to the page (first frames show; no copies)
spec = importlib.util.spec_from_file_location("bp", os.path.join(ROOT, "site/progress/build_progress.py"))
bp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bp)
bp.build()
for name, rel in bp.local_sources().items():
    dst = os.path.join(pdir, name)
    if os.path.lexists(dst):
        os.remove(dst)
    os.symlink(os.path.join(ROOT, rel), dst)

page = open(html_path).read()


def wrap(theme):
    return (f'<!doctype html><html lang="en" data-theme="{theme}"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width, initial-scale=1"></head>'
            f'<body style="margin:0">{page}</body></html>')


MEASURE = """<!doctype html><meta charset="utf-8"><body style="margin:0">
<iframe id="f" src="__SRC__" width="__W__" height="400" style="border:0;display:block"></iframe><pre id="o"></pre>
<script>
document.getElementById('f').addEventListener('load', function () {
  setTimeout(function () {
    var doc = document.getElementById('f').contentDocument, d = doc.documentElement, W = __W__, wide = [];
    doc.querySelectorAll('body *').forEach(function (e) {
      var r = e.getBoundingClientRect();
      if (r.right > W + 1 && getComputedStyle(e).position !== 'fixed') {
        var p = e.parentElement, clip = false;
        while (p) { var o = getComputedStyle(p).overflowX; if (o === 'auto' || o === 'scroll' || o === 'hidden') { clip = true; break; } p = p.parentElement; }
        if (!clip) wide.push(e.tagName + '.' + e.className + ' ' + Math.round(r.right));
      }
    });
    document.getElementById('o').textContent = JSON.stringify({h: d.scrollHeight, sw: d.scrollWidth, wide: wide.slice(0, 12)});
  }, 1500);
});
</script>"""

SECTION = """<!doctype html><meta charset="utf-8"><body style="margin:0;background:#888">
<div id="box" style="overflow:hidden;height:__H__px;width:__W__px"><iframe id="f" src="__SRC__" width="__W__" height="400" style="border:0;display:block"></iframe></div>
<script>
var f = document.getElementById('f');
f.addEventListener('load', function () {
  setTimeout(function () {
    var doc = f.contentDocument, el = doc.getElementById('__ID__');
    f.style.height = doc.documentElement.scrollHeight + 'px';
    setTimeout(function () {
      var top = el ? el.getBoundingClientRect().top + doc.defaultView.scrollY : 0;
      f.style.marginTop = (-(top - 12)) + 'px';
    }, 400);
  }, 1500);
});
</script>"""

for th in ("light", "dark"):
    open(os.path.join(pdir, f"{th}.html"), "w").write(wrap(th))
    for w in (1200, 390):
        open(os.path.join(pdir, f"m{w}_{th}.html"), "w").write(MEASURE.replace("__SRC__", f"{th}.html").replace("__W__", str(w)))
    for sid in IDS:
        open(os.path.join(pdir, f"sec_{sid}_{th}.html"), "w").write(
            SECTION.replace("__SRC__", f"{th}.html").replace("__W__", "390").replace("__H__", str(SECH)).replace("__ID__", sid))


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a, **k):
        pass


socketserver.ThreadingTCPServer.allow_reuse_address = False
srv = socketserver.ThreadingTCPServer(("127.0.0.1", port), functools.partial(Quiet, directory=pdir))
threading.Thread(target=srv.serve_forever, daemon=True).start()
try:
    served = urllib.request.urlopen(f"http://127.0.0.1:{port}/light.html").read().decode()
    n = served.count(marker)
    print(f"served page marker {marker!r}: {n} occurrence(s) (page file: {page.count(marker)})")
    assert n >= 1 and n == page.count(marker), "the served page is not the page under test"

    def chrome(args, timeout=150):
        cmd = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run"] + args
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

    for kind, w in (("desktop", 1200), ("phone", 390)):
        if only and only != kind:
            continue
        for th in ("light", "dark"):
            r = chrome(["--dump-dom", "--virtual-time-budget=9000", "--window-size=1300,900", f"http://127.0.0.1:{port}/m{w}_{th}.html"])
            m = re.search(r'<pre id="o">(.*?)</pre>', r.stdout, re.S)
            raw = m.group(1).replace("&quot;", '"').replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">") if m else ""
            info = json.loads(raw) if raw.strip() else {}
            print(kind, th, "measure:", info)
            h = int(info.get("h", 14000)) + 20
            png = os.path.join(shots, f"{tag}_{kind}_{th}.png")
            if kind == "desktop":
                chrome([f"--window-size={w},{min(h, 16000)}", "--virtual-time-budget=6000", f"--screenshot={png}", f"http://127.0.0.1:{port}/{th}.html"])
            else:
                chrome([f"--window-size=500,{min(h + 60, 16000)}", "--virtual-time-budget=9000", f"--screenshot={png}", f"http://127.0.0.1:{port}/m{w}_{th}.html"])
            print("  wrote", png, os.path.getsize(png) if os.path.exists(png) else "MISSING")
    for sid in IDS:
        for th in ("light", "dark"):
            png = os.path.join(shots, f"{tag}_sec_{sid}_{th}.png")
            chrome([f"--window-size=400,{SECH}", "--virtual-time-budget=9000", f"--screenshot={png}", f"http://127.0.0.1:{port}/sec_{sid}_{th}.html"])
            print("  wrote", png, os.path.getsize(png) if os.path.exists(png) else "MISSING")
finally:
    srv.shutdown()
    srv.server_close()
