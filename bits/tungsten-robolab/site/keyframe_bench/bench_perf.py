#!/usr/bin/env python3
"""Real-time cost of one Keyframe Bench refresh (what runs on every pointer move while a joint is dragged), via Chrome's DevTools protocol.

    .venv/bin/python site/keyframe_bench/bench_perf.py

Headless virtual time cannot time anything (performance.now() is virtual there), so this drives a real-time headless Chrome.
"""
import glob
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_bench  # noqa: E402

from websockets.sync.client import connect  # noqa: E402

PORT = 9333


def main():
    seed = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(HERE, "seed", "*.json")))]
    d = tempfile.mkdtemp(prefix="kfperf_")
    path = os.path.join(d, "index.html")
    page = check_bench.build(seed).replace(check_bench.TEST, "")
    open(path, "w").write(page)
    prof = tempfile.mkdtemp(prefix="kfperf_prof_")
    chrome = subprocess.Popen([check_bench.CHROME, "--headless=new", "--disable-gpu", f"--remote-debugging-port={PORT}", f"--user-data-dir={prof}",
                               "--window-size=1200,1500", "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        ws_url = None
        for _ in range(60):
            try:
                tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json/list", timeout=2))
                pages = [t for t in tabs if t.get("type") == "page"]
                if pages:
                    ws_url = pages[0]["webSocketDebuggerUrl"]
                    break
            except Exception:
                pass
            time.sleep(0.25)
        assert ws_url, "Chrome did not start"
        with connect(ws_url, max_size=None) as ws:
            n = [0]

            def call(method, params=None):
                n[0] += 1
                ws.send(json.dumps({"id": n[0], "method": method, "params": params or {}}))
                while True:
                    m = json.loads(ws.recv())
                    if m.get("id") == n[0]:
                        return m

            call("Page.enable")
            call("Page.navigate", {"url": "file://" + path})
            time.sleep(1.5)
            js = """(async () => {
              const B = window.__bench, out = {};
              await new Promise(r => setTimeout(r, 600));
              for (const setId of ['run_natural', 'bolt_sprint']) {
                B.state.setId = setId; B.state.idx = 1; B.chrome();
                for (let i = 0; i < 10; i++) B.refresh();
                const t0 = performance.now(); for (let i = 0; i < 100; i++) B.refresh();
                out[setId + '_full_refresh_ms'] = Math.round((performance.now() - t0) * 10) / 1000;
                const t1 = performance.now(); for (let i = 0; i < 100; i++) B.refreshView();
                out[setId + '_view_only_ms'] = Math.round((performance.now() - t1) * 10) / 1000;
                out[setId + '_svg_elements'] = document.getElementById('fig').querySelectorAll('*').length + document.getElementById('strip').querySelectorAll('*').length;
              }
              return out;
            })()"""
            r = call("Runtime.evaluate", {"expression": js, "awaitPromise": True, "returnByValue": True})
            print(json.dumps(r.get("result", r).get("result", r), indent=1))
    finally:
        chrome.terminate()


if __name__ == "__main__":
    main()
