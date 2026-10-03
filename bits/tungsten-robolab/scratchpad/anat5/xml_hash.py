"""Build the scene XML of a list of (task, body env) combinations, each in a FRESH interpreter with exactly that environment,
and print `task | env label | sha256 | bytes`. Used for the byte-identity proof of a data-only calibration (run before and after
the calibration file exists; the two outputs must be identical, line by line).

    .venv/bin/python scratchpad/anat5/xml_hash.py OUT.txt
"""
import hashlib, os, subprocess, sys

P95 = {"ROBOLAB_PROFILE": "p95", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"}
E2 = {"ROBOLAB_PROFILE": "elite2", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"}
SPR = {"ROBOLAB_PROFILE": "sprinter", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"}
V4 = {"ROBOLAB_CALIB": "v4"}
COMBOS = [
    ("run_v3", "plain", {}),
    ("run_v3", "p95", dict(P95)),
    ("run_v2", "plain", {}),
    ("run_v4", "calib unset (task default v4)", {}),
    ("run_v4", "calib v4", dict(V4)),
    ("run_v4", "calib v4 p95", {**V4, **P95}),
    ("run_v4", "calib v4 elite2", {**V4, **E2}),
    ("run_v4", "calib v4 sprinter", {**V4, **SPR}),
    ("run_v4", "calib v4 p95 (ROBOLAB_BODY=v4)", {**V4, **P95, "ROBOLAB_BODY": "v4"}),
    ("sprint_touch_v4", "calib v4 p95", {**V4, **P95}),
    ("sprint_touch_v4x", "calib v4 p95", {**V4, **P95}),
    ("long_jump", "plain", {}),
    ("long_jump_v4_p95", "calib v4 p95", {**V4, **P95}),
    ("long_jump_v4_elite2", "calib v4 elite2", {**V4, **E2}),
    ("long_jump_run", "plain", {}),
    ("bat", "plain", {}),
    ("bat_v6", "plain", {}),
    ("hurdle_hs_v3", "plain", {}),
    ("run_natural_fast_v3", "plain", {}),
]
SNIPPET = r"""
import sys, hashlib, importlib
sys.path.insert(0, "playground")
t = importlib.import_module("tasks." + sys.argv[1]).TASK()
x = t.xml(t.builder())
print(hashlib.sha256(x.encode()).hexdigest(), len(x.encode()))
"""
out = sys.argv[1]
base = {k: v for k, v in os.environ.items() if not k.startswith("ROBOLAB_") and k not in ("RUN_NATURAL_START",)}
lines = []
for task, label, env in COMBOS:
    e = dict(base); e.update(env)
    r = subprocess.run([".venv/bin/python", "-c", SNIPPET, task], env=e, capture_output=True, text=True)
    res = r.stdout.strip() if r.returncode == 0 else "ERROR " + (r.stderr.strip().splitlines() or ["?"])[-1][:120]
    sha = res.split()[0] if r.returncode == 0 else res
    n = res.split()[1] if r.returncode == 0 else ""
    lines.append(f"{task} | {label} | {sha} | {n}")
    print(lines[-1], flush=True)
open(out, "w").write("\n".join(lines) + "\n")
