#!/usr/bin/env python3
"""DOM checks of the progress page in headless Chrome (agent P9, 3 Oct 2026).

    python3 scratchpad/progress29/jstest.py PORT HTML

Serves the page from a thread of this process, loads it in iframes of 1200 px and 390 px (light and dark theme) and writes
into a <pre>: for every chart row whether its bar is drawn to scale (bar px = value / axis max x plot px), whether its value
label stays inside its row and clear of its bar, whether a label is clipped, and whether the table toggle of every chart works.
Nothing keeps running after it exits.
"""
import functools
import http.server
import json
import os
import re
import socketserver
import subprocess
import sys
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
port, html_path = int(sys.argv[1]), sys.argv[2]
pdir = os.path.join(HERE, "jstest_dir")
os.makedirs(pdir, exist_ok=True)
page = open(html_path).read()
AXIS = {"c-sprint": 15, "c-jump": 10, "c-jump-beyond": 12, "c-bat": 40, "c-tt": 100}     # axis maxima of build_progress.py
for th in ("light", "dark"):
    open(os.path.join(pdir, f"{th}.html"), "w").write(
        f'<!doctype html><html lang="en" data-theme="{th}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>'
        f'<body style="margin:0">{page}</body></html>')

TEST = """<!doctype html><meta charset="utf-8"><body style="margin:0">
<iframe id="f" src="__SRC__" width="__W__" height="900" style="border:0;display:block"></iframe><pre id="o">pending</pre>
<script>
var AXIS = __AXIS__;
function check(doc) {
  var out = {rows: 0, bad: [], toggles: [], clipped: []};
  Object.keys(AXIS).forEach(function (id) {
    var fig = doc.getElementById(id);
    if (!fig) { out.bad.push(id + ': missing'); return; }
    fig.querySelectorAll('.crow').forEach(function (row) {
      out.rows++;
      var plot = row.querySelector('.cplot'), bar = row.querySelector('.cbar, .ctrack'), val = row.querySelector('.cval');
      var v = parseFloat(row.dataset.v), pw = plot.getBoundingClientRect().width, bw = bar.getBoundingClientRect().width;
      var expect = v / AXIS[id] * pw;
      if (Math.abs(bw - expect) > 1.5) out.bad.push(id + ' ' + row.dataset.l + ': bar ' + bw.toFixed(1) + ' px, expected ' + expect.toFixed(1));
      var shown = parseFloat(val.textContent);
      if (Math.abs(shown - v) > 0.0005 * Math.max(1, v)) out.bad.push(id + ' ' + row.dataset.l + ': label ' + val.textContent + ' vs value ' + row.dataset.v);
      var rr = row.getBoundingClientRect(), vr = val.getBoundingClientRect(), br = bar.getBoundingClientRect();
      if (vr.right > rr.right + 0.5 || vr.left < rr.left - 0.5) out.bad.push(id + ' ' + row.dataset.l + ': label outside its row (' + vr.right.toFixed(0) + ' > ' + rr.right.toFixed(0) + ')');
      if (vr.left < br.right - 0.5) out.bad.push(id + ' ' + row.dataset.l + ': label overlaps its bar');
      var cl = row.querySelector('.clabel');
      if (cl.scrollWidth > cl.clientWidth + 1) out.clipped.push(id + ' ' + row.dataset.l);
    });
    var btn = fig.querySelector('.tbtn'), cv = fig.querySelector('.cview'), tv = fig.querySelector('.tview');
    btn.click();
    var after1 = {chartHidden: cv.hidden, tableHidden: tv.hidden, text: btn.textContent, pressed: btn.getAttribute('aria-pressed')};
    var tw = tv.querySelector('.tablewrap');
    var rowsInTable = tv.querySelectorAll('tr').length - 1;
    btn.click();
    out.toggles.push({id: id, toTable: after1, back: {chartHidden: cv.hidden, tableHidden: tv.hidden, text: btn.textContent}, tableRows: rowsInTable, chartRows: fig.querySelectorAll('.crow').length});
  });
  // text that sticks out of its card or the viewport, outside scroll containers
  var W = doc.documentElement.clientWidth, over = [];
  doc.querySelectorAll('.side *, .media figcaption *, .slot *, .chart *').forEach(function (e) {
    var r = e.getBoundingClientRect();
    if (r.width && r.right > W + 1) {
      var p = e.parentElement, clip = false;
      while (p) { var o = getComputedStyle(p).overflowX; if (o === 'auto' || o === 'scroll' || o === 'hidden') { clip = true; break; } p = p.parentElement; }
      if (!clip) over.push(e.tagName + '.' + e.className + ' ' + Math.round(r.right));
    }
  });
  out.overflow = over.slice(0, 10);
  out.scrollWidth = doc.documentElement.scrollWidth;
  return out;
}
var f = document.getElementById('f');
f.addEventListener('load', function () {
  setTimeout(function () {
    try { document.getElementById('o').textContent = JSON.stringify(check(f.contentDocument)); }
    catch (e) { document.getElementById('o').textContent = 'ERROR ' + e + ' ' + e.stack; }
  }, 1500);
});
</script>"""
for th in ("light", "dark"):
    for w in (1200, 390):
        open(os.path.join(pdir, f"t{w}_{th}.html"), "w").write(
            TEST.replace("__SRC__", f"{th}.html").replace("__W__", str(w)).replace("__AXIS__", json.dumps(AXIS)))


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a, **k):
        pass


socketserver.ThreadingTCPServer.allow_reuse_address = False
srv = socketserver.ThreadingTCPServer(("127.0.0.1", port), functools.partial(Quiet, directory=pdir))
threading.Thread(target=srv.serve_forever, daemon=True).start()
try:
    for th in ("light", "dark"):
        for w in (1200, 390):
            r = subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-first-run", "--dump-dom", "--virtual-time-budget=9000",
                                "--window-size=1300,900", f"http://127.0.0.1:{port}/t{w}_{th}.html"], capture_output=True, text=True, timeout=150)
            m = re.search(r'<pre id="o">(.*?)</pre>', r.stdout, re.S)
            raw = (m.group(1) if m else "NO OUTPUT").replace("&quot;", '"').replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
            try:
                d = json.loads(raw)
                tog = all((not t["toTable"]["tableHidden"]) and t["toTable"]["chartHidden"] and t["toTable"]["text"] == "Chart" and t["back"]["text"] == "Table"
                          and (not t["back"]["chartHidden"]) and t["back"]["tableHidden"] and t["tableRows"] == t["chartRows"] for t in d["toggles"])
                print(f"{w} px {th}: rows {d['rows']}, to-scale/label problems {len(d['bad'])}, clipped labels {len(d['clipped'])}, "
                      f"toggles ok {tog} ({len(d['toggles'])} charts), sticks out {len(d['overflow'])}, scrollWidth {d['scrollWidth']}")
                for x in d["bad"] + ["clipped: " + c for c in d["clipped"]] + ["overflow: " + o for o in d["overflow"]]:
                    print("    ", x)
            except ValueError:
                print(w, th, "UNPARSED:", raw[:400])
finally:
    srv.shutdown()
    srv.server_close()
