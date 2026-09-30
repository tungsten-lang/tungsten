#!/usr/bin/env python3
"""Headless check of the Keyframe Bench page against a mock database seeded with the seed docs.

    python3 site/keyframe_bench/check_bench.py [--shot light|dark OUT.png] [--width 1200]

Builds a copy of keyframe_bench.html with a mock `window.claude` (db + user), a test script and a results <pre>,
runs it in headless Chrome (virtual time) and prints the results the page wrote. Exit code 1 if any check failed.
"""
import glob
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

MOCK = r"""
<script>
(function () {
  var store = new Map(), listeners = [];
  var SEED = __SEED__;
  SEED.forEach(function (d) { store.set(d.set + '.' + d.event, d); });
  function snap() { var docs = []; store.forEach(function (v, id) { docs.push({ id: id, data: function () { return JSON.parse(JSON.stringify(v)); } }); }); return { size: docs.length, docs: docs }; }
  function merge(a, b) { var o = JSON.parse(JSON.stringify(a)); Object.keys(b).forEach(function (k) { o[k] = (b[k] && typeof b[k] === 'object' && !Array.isArray(b[k]) && o[k] && typeof o[k] === 'object') ? merge(o[k], b[k]) : b[k]; }); return o; }
  function fire() { listeners.forEach(function (cb) { cb(snap()); }); }
  window.__store = store; window.__writes = [];
  // headless virtual time paints no frames: run animation callbacks off timers instead
  window.requestAnimationFrame = function (cb) { return setTimeout(function () { cb(performance.now()); }, 16); };
  window.cancelAnimationFrame = function (id) { clearTimeout(id); };
  var db = {
    collection: function () { return { onSnapshot: function (cb) { listeners.push(cb); cb(snap()); return function () {}; } }; },
    doc: function (path) { var id = path.split('/')[1]; return {
      update: function (body) { window.__writes.push(['update', id]); var cur = store.get(id); if (!cur) return Promise.reject({ code: 'not_found' }); store.set(id, merge(cur, body)); fire(); return Promise.resolve(); },
      set: function (body) { window.__writes.push(['set', id]); store.set(id, JSON.parse(JSON.stringify(body))); fire(); return Promise.resolve(); },
      remove: null,
      delete: function () { window.__writes.push(['delete', id]); store.delete(id); fire(); return Promise.resolve(); } }; }
  };
  window.claude = { use: function (n) { return Promise.resolve(n === 'db' ? db : n === 'user' ? { can: function () { return Promise.resolve(true); } } : null); } };
})();
</script>
"""

TEST = r"""
<pre id="results" style="position:fixed;left:0;bottom:0;background:#fff;color:#000;z-index:99;font:11px monospace;max-width:100%;white-space:pre-wrap;opacity:0"></pre>
<script>
window.addEventListener('load', async function () {
  var out = [], fails = 0;
  function ok(name, cond, extra) { if (!cond) fails++; out.push((cond ? 'PASS ' : 'FAIL ') + name + (extra !== undefined ? '  [' + JSON.stringify(extra) + ']' : '')); document.getElementById('results').textContent = out.join('\n'); }
  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  var errors = []; window.addEventListener('error', function (e) { errors.push(String(e.message)); });
  await sleep(400);
  var B = window.__bench, st = B.state, fig = document.getElementById('fig'), strip = document.getElementById('strip');
  ok('db sets loaded', Object.keys(st.sets).length === 2 && st.sets.run_natural.events.length === 5 && st.sets.bolt_sprint.events.length === 15, Object.keys(st.sets));
  ok('no page errors', errors.length === 0, errors);
  ok('the editor canvas has no onion skin (no ghost paths)', fig.querySelectorAll('path').length === 0, fig.querySelectorAll('path').length);
  ok('the strip is the onion skin (ghost paths)', strip.querySelectorAll('path').length >= 16 * 2, strip.querySelectorAll('path').length);
  ok('no onion or paths toggles in the editor legend', !document.getElementById('showOnion') && !document.getElementById('showTrails'));
  ok('a pins grid cell per joint and keyframe', document.querySelectorAll('button.pinb').length === 14 * 5);
  // kl is a subset keyframe: 1 of 14 pinned
  var kl = st.sets.run_natural.events.find(function (e) { return e.event === 'kl'; });
  st.idx = st.sets.run_natural.events.indexOf(kl); B.refresh();
  ok('kl shows 1 of 14 joints pinned', /1 of 14 joints pinned/.test(document.getElementById('evNote').textContent), document.getElementById('evNote').textContent);
  var d = B.displayAngles(kl);
  ok('kl pinned swing hip kept (68.5), free joints follow the animation', d.sw_hip === 68.5 && d.st_hip !== kl.angles.st_hip, { sw_hip: d.sw_hip, st_hip: d.st_hip, saved_st_hip: kl.angles.st_hip });
  // timing of a full refresh
  var t0 = performance.now(); for (var i = 0; i < 40; i++) B.refresh(); var ms = (performance.now() - t0) / 40;
  ok('refresh under 25 ms', ms < 25, Math.round(ms * 10) / 10);
  // pinning through the table
  st.idx = 0; B.refresh();
  var td = st.sets.run_natural.events[0];
  var cb = document.getElementById('pin_st_hip'); ok('pin checkbox present and checked', cb && cb.checked);
  cb.checked = false; cb.dispatchEvent(new Event('change', { bubbles: true })); await sleep(50);
  ok('unpinning st_hip at td took effect (draft, or already in the store)', (st.localPin[td.id] && st.localPin[td.id].st_hip === false) || (td.pinned && td.pinned.st_hip === false) || (window.__store.get('run_natural.td').pinned || {}).st_hip === false);
  ok('free row is styled', document.querySelector('#in_st_hip').classList.contains('isfree'));
  await sleep(50);
  var saved = window.__store.get('run_natural.td');
  ok('unpin saved to the database', saved && saved.pinned && saved.pinned.st_hip === false && saved.pinned.st_knee === true, saved && saved.pinned);
  var free = B.displayAngles(st.sets.run_natural.events[0]).st_hip;
  ok('freed joint follows the neighbours (not 36)', Math.abs(free - 36) > 0.5, free);
  // typing a value pins it again
  var inp = document.getElementById('in_st_hip'); inp.value = '20'; inp.dispatchEvent(new Event('change', { bubbles: true })); await sleep(400);
  saved = window.__store.get('run_natural.td');
  ok('typing pins and saves', saved.pinned.st_hip === true && saved.angles.st_hip === 20, { pinned: saved.pinned.st_hip, v: saved.angles.st_hip });
  // dope-sheet cell
  var cell = document.querySelector('button.pinb[data-e="1"][data-k="st_toe"]'); cell.click(); await sleep(50);
  ok('grid cell frees st_toe at ms', window.__store.get('run_natural.ms').pinned.st_toe === false, window.__store.get('run_natural.ms').pinned);
  // only what I changed, at toe-off
  st.idx = 3; B.refresh(); document.getElementById('pinChanged').click(); await sleep(50);
  var to = window.__store.get('run_natural.to'); var nPinned = Object.values(to.pinned).filter(Boolean).length;
  ok('only-what-I-changed pins a subset at toe-off', nPinned > 0 && nPinned < 14, nPinned);
  // dragging a handle pins the joint
  st.idx = 0; B.refresh();
  var h = fig.querySelector('circle[data-h="1"]'); var r = h.getBoundingClientRect();
  var cx = r.left + r.width / 2, cy = r.top + r.height / 2, before = B.displayAngles(st.sets.run_natural.events[0]).st_knee;
  h.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, clientX: cx, clientY: cy, pointerId: 1, button: 0 }));
  fig.dispatchEvent(new PointerEvent('pointermove', { bubbles: true, clientX: cx + 30, clientY: cy + 10, pointerId: 1 }));
  await sleep(60);
  fig.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, clientX: cx + 30, clientY: cy + 10, pointerId: 1 })); await sleep(400);
  var after = window.__store.get('run_natural.td').angles.st_knee;
  ok('drag moved a joint and saved it', Math.abs(after - before) > 1, { before: before, after: after });
  // the onion skin follows an edit in real time: the ghost paths change when a pinned value changes
  var sig = function () { return Array.prototype.map.call(strip.querySelectorAll('path'), function (p) { return p.getAttribute('d'); }).join('|'); };
  var s1 = sig(); inp = document.getElementById('in_st_hip'); inp.value = '10'; inp.dispatchEvent(new Event('change', { bubbles: true })); await sleep(50);
  ok('the onion skin (strip) redraws after an edit', sig() !== s1);
  // export
  document.getElementById('copy').click(); await sleep(100);
  var txt = document.getElementById('out').value;
  ok('export lists every keyframe with a phase', (txt.match(/_phase /g) || []).length === 5, (txt.match(/_phase /g) || []).length);
  ok('export flags free joints (kl: 13)', (txt.match(/ref_kl_[a-z_]+_free 1/g) || []).length === 13, (txt.match(/ref_kl_[a-z_]+_free 1/g) || []).length);
  ok('export gives free joints the animation value', /ref_kl_st_hip -?\d/.test(txt) && !/ref_kl_st_hip 0\.0\b/.test(txt), (txt.match(/ref_kl_st_hip [^\n]+/) || [''])[0]);
  // add a keyframe: pins nothing
  document.getElementById('addBtn').click(); document.getElementById('addName').value = 'Foot flat'; document.getElementById('addPct').value = '9';
  document.getElementById('addForm').dispatchEvent(new Event('submit', { cancelable: true, bubbles: true })); await sleep(150);
  var nd = window.__store.get('run_natural.foot_flat');
  ok('added keyframe pins nothing', nd && Object.values(nd.pinned).every(function (v) { return v === false; }) && nd.phase_pct === 9, nd && nd.pinned);
  ok('added keyframe selected', cur_label() === 'Foot flat', cur_label());
  function cur_label() { var c = B.cur(); return c && c.label; }
  // playback and scrub
  document.getElementById('play').click(); await sleep(250);
  ok('playing shows a moving playhead', st.playing && st.playQ !== null && st.playQ > 0, st.playQ);
  document.getElementById('play').click(); await sleep(50);
  ok('stopped', !st.playing && st.playQ === null);
  var rect = strip.getBoundingClientRect();
  strip.dispatchEvent(new PointerEvent('pointermove', { bubbles: true, clientX: rect.left + rect.width * 0.5, clientY: rect.top + rect.height * 0.5, pointerId: 1 })); await sleep(40);
  ok('scrubbing sets a phase', st.scrubQ !== null && st.scrubQ > 30 && st.scrubQ < 70, st.scrubQ);
  var blue = function (root, tag) { return Array.prototype.filter.call(root.querySelectorAll(tag), function (n) { return n.getAttribute('stroke') === 'var(--accent)'; }).length; };
  ok('the blue scrub figure shows over the pose in the editor', blue(fig, 'polyline') > 0, blue(fig, 'polyline'));
  ok('the blue scrub figure shows in the strip too', blue(strip, 'path') > 0, blue(strip, 'path'));
  ok('the editor still has no onion paths while scrubbing', fig.querySelectorAll('path').length === 0);
  // the blue figure never sinks into the ground: its lowest point is on the ground line (editor y 640, strip y 170), for every phase
  var worstEditor = -1e9, worstStrip = -1e9, lowEditor = 1e9;
  for (var q = 0; q <= 100; q += 5) {
    st.scrubQ = q; B.refreshView();
    Array.prototype.forEach.call(fig.querySelectorAll('polyline'), function (pl) {
      if (pl.getAttribute('stroke') !== 'var(--accent)') return;
      var ys = pl.getAttribute('points').split(' ').map(function (p) { return parseFloat(p.split(',')[1]); });
      var m = Math.max.apply(null, ys); worstEditor = Math.max(worstEditor, m);
    });
    var lowest = -1e9;
    Array.prototype.forEach.call(fig.querySelectorAll('polyline'), function (pl) { if (pl.getAttribute('stroke') === 'var(--accent)') lowest = Math.max(lowest, Math.max.apply(null, pl.getAttribute('points').split(' ').map(function (p) { return parseFloat(p.split(',')[1]); }))); });
    lowEditor = Math.min(lowEditor, lowest);
    Array.prototype.forEach.call(strip.querySelectorAll('path'), function (pa) {
      if (pa.getAttribute('stroke') !== 'var(--accent)') return;
      var nums = pa.getAttribute('d').match(/-?\d+\.?\d*/g).map(parseFloat);
      for (var i = 1; i < nums.length; i += 2) worstStrip = Math.max(worstStrip, nums[i]);
    });
  }
  ok('the blue figure in the editor never goes below the ground line (y 640)', worstEditor <= 640.6, worstEditor);
  ok('the blue figure in the editor always stands on it (lowest point within 1 px of the ground)', lowEditor >= 639, lowEditor);
  ok('the blue figure in the strip never goes below the strip ground (y 170)', worstStrip <= 170.6, worstStrip);
  st.scrubQ = null; B.refreshView();
  strip.dispatchEvent(new PointerEvent('pointerleave', { bubbles: true })); await sleep(20);
  // switch to the non-cyclic set
  st.setId = 'bolt_sprint'; st.idx = 0; B.refresh();
  ok('non-cyclic set renders', fig.querySelectorAll('polyline').length > 0 && strip.querySelectorAll('path').length >= 16 * 2 && document.querySelectorAll('button.pinb').length === 14 * 15, strip.querySelectorAll('path').length);
  ok('no page errors at the end', errors.length === 0, errors);
  out.push('DONE fails=' + fails); document.getElementById('results').textContent = out.join('\n');
});
</script>
"""


def build(seed, light_dark=None):
    page = open(os.path.join(HERE, "keyframe_bench.html")).read()
    skel = ('<!doctype html><html' + (f' data-theme="{light_dark}"' if light_dark else '') + '><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
            '<style>:root{color-scheme:light}body{margin:0;font:14px system-ui,sans-serif;background:#fafafa}[hidden]{display:none!important}</style>'
            + MOCK.replace("__SEED__", json.dumps(seed)) + '</head><body>' + page + TEST + '</body></html>')
    return skel


def main():
    seed = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(HERE, "seed", "*.json")))]
    width = int(sys.argv[sys.argv.index("--width") + 1]) if "--width" in sys.argv else 1200
    d = tempfile.mkdtemp(prefix="kfbench_")
    path = os.path.join(d, "index.html")
    open(path, "w").write(build(seed))
    if "--real" in sys.argv:
        page = open(path).read().replace("window.requestAnimationFrame = function (cb) { return setTimeout(function () { cb(performance.now()); }, 16); };", "").replace("window.cancelAnimationFrame = function (id) { clearTimeout(id); };", "")
        open(path, "w").write(page)
        flags = ["--timeout=14000"]
    else:
        flags = ["--virtual-time-budget=20000"]
    r = subprocess.run([CHROME, "--headless=new", "--disable-gpu", f"--window-size={width},1500"] + flags + ["--dump-dom", "file://" + path],
                       capture_output=True, text=True, timeout=180)
    import re
    m = re.search(r'<pre id="results"[^>]*>(.*?)</pre>', r.stdout, re.S)
    text = re.sub(r"<[^>]+>", "", m.group(1)) if m else "no results in the DOM\n" + r.stderr[-500:]
    import html
    text = html.unescape(text)
    print(text)
    if "--shot" in sys.argv:
        theme = sys.argv[sys.argv.index("--shot") + 1]; outp = sys.argv[sys.argv.index("--shot") + 2]
        shot_html = os.path.join(d, "shot.html")
        sel = ""
        if "--event" in sys.argv:
            set_id = sys.argv[sys.argv.index("--set") + 1] if "--set" in sys.argv else "run_natural"
            ev_id = sys.argv[sys.argv.index("--event") + 1]
            sel = ("<script>window.addEventListener('load', function () { setTimeout(function () { var B = window.__bench; B.state.setId = '%s'; "
                   "B.state.idx = Math.max(0, B.state.sets['%s'].events.findIndex(function (e) { return e.event === '%s'; })); B.chrome(); B.refresh(); }, 300); });</script>" % (set_id, set_id, ev_id))
        if "--scrub" in sys.argv:
            sel += ("<script>window.addEventListener('load', function () { setTimeout(function () { var B = window.__bench; B.state.scrubQ = %s; B.refreshView(); }, 500); });</script>" % sys.argv[sys.argv.index("--scrub") + 1])
        open(shot_html, "w").write(build(seed, theme).replace("</body>", "").replace(TEST, "") + sel + "</body></html>")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--window-size={width},1900", "--virtual-time-budget=6000", f"--screenshot={outp}", "file://" + shot_html],
                       capture_output=True, text=True, timeout=180)
        print("screenshot", outp)
    sys.exit(0 if "DONE fails=0" in text else 1)


if __name__ == "__main__":
    main()
