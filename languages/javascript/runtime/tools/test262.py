#!/usr/bin/env python3
"""Drive the test262 runner over directories, surviving crashes and hangs.

usage: test262.py RUNNER_BINARY TEST262_ROOT OUT_FILE dir [dir...]
Prints pass rates per directory (relative to test/)."""
import os, subprocess, sys, tempfile, collections

runner, root, out_file = sys.argv[1], sys.argv[2], sys.argv[3]
dirs = sys.argv[4:]
tests = []
for d in dirs:
    base = os.path.join(root, "test", d)
    for dp, dn, fn in os.walk(base):
        dn.sort()
        for f in sorted(fn):
            if f.endswith(".js") and "_FIXTURE" not in f:
                tests.append(os.path.relpath(os.path.join(dp, f), os.path.join(root, "test")))
results = {}
i = 0
BATCH = 150
while i < len(tests):
    batch = tests[i:i + BATCH]
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".txt") as tf:
        tf.write("\n".join(batch))
        lst = tf.name
    try:
        p = subprocess.run([runner, root, lst], capture_output=True, text=True, timeout=max(30, len(batch) // 2), errors="replace")
        out = p.stdout
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
    done = 0
    for line in out.splitlines():
        parts = line.split(" ", 2)
        if len(parts) >= 2 and parts[0] in ("PASS", "FAIL", "SKIP"):
            results[parts[1]] = line
            done += 1
    os.unlink(lst)
    if done < len(batch):
        # the test after the last reported one crashed or hung
        bad = batch[done]
        results[bad] = "FAIL " + bad + " crash-or-timeout"
        i += done + 1
    else:
        i += len(batch)
    sys.stderr.write("\r%d/%d" % (min(i, len(tests)), len(tests)))
sys.stderr.write("\n")
with open(out_file, "w") as f:
    for t in tests:
        f.write(results.get(t, "FAIL " + t + " missing") + "\n")
stats = collections.OrderedDict()
for t in tests:
    parts = t.split("/")
    key = "/".join(parts[:3]) if len(parts) > 3 else "/".join(parts[:2])
    s = stats.setdefault(key, [0, 0, 0])
    r = results.get(t, "FAIL")
    if r.startswith("PASS"): s[0] += 1
    elif r.startswith("SKIP"): s[2] += 1
    else: s[1] += 1
tp = tf_ = ts = 0
for k, (p, f, s) in stats.items():
    tp += p; tf_ += f; ts += s
    run = p + f
    print("%-55s %5d/%5d  %5.1f%%  (skip %d)" % (k, p, run, 100.0 * p / run if run else 0, s))
run = tp + tf_
print("%-55s %5d/%5d  %5.1f%%  (skip %d)" % ("TOTAL", tp, run, 100.0 * tp / run if run else 0, ts))
