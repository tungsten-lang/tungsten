"""Build the run_v4 scene XML for two calibrations (same profile env) and list every element / attribute that differs, plus the joint totals."""
import hashlib, os, subprocess, sys, xml.etree.ElementTree as ET
SNIP = r"""
import sys, importlib
sys.path.insert(0, "playground")
t = importlib.import_module("tasks.run_v4").TASK()
sys.stdout.write(t.xml(t.builder()))
"""
def build(calib, extra=None):
    env = {k: v for k, v in os.environ.items() if not k.startswith("ROBOLAB_")}
    env.update({"ROBOLAB_CALIB": calib, "ROBOLAB_PROFILE": "p95", "ROBOLAB_PROFILE_PARTS": "strength,speed,tendon,activation"})
    if extra: env.update(extra)
    return subprocess.run([".venv/bin/python", "-c", SNIP], env=env, capture_output=True, text=True, check=True).stdout
a, b = build(sys.argv[1]), build(sys.argv[2])
print("sha256", sys.argv[1], hashlib.sha256(a.encode()).hexdigest()[:16], " ", sys.argv[2], hashlib.sha256(b.encode()).hexdigest()[:16])
ra, rb = ET.fromstring(a), ET.fromstring(b)
ea, eb = list(ra.iter()), list(rb.iter())
print("elements", len(ea), len(eb))
n = 0
for x, y in zip(ea, eb):
    if x.tag != y.tag or x.attrib.keys() != y.attrib.keys():
        print("STRUCTURE differs at", x.tag, y.tag); n += 1; continue
    d = {k: (x.attrib[k], y.attrib[k]) for k in x.attrib if x.attrib[k] != y.attrib[k]}
    if d:
        name = x.attrib.get("name") or x.attrib.get("joint") or ""
        print(f"  {x.tag:8s} {name:22s}", {k: v for k, v in d.items()})
        n += 1
print("differing elements:", n)
