#!/usr/bin/env python3
"""Job queue daemon: runs tt_eval.py jobs listed in scratchpad/tt/jobs.jsonl one at a time (3 workers each).

Each line: {"tag": ..., "ctl": ..., "params": ..., "seeds": "a:b", "set": "k=v,...", "env": {"NAME": "VALUE"}, "log": true}
A job is finished when out/tt_r10/<tag>.log contains a summary line ('{'). Append lines any time; touch scratchpad/tt/qd.stop to end.
"""
import json, os, subprocess, sys, time
ROOT = "/Users/erik/tungsten/bits/tungsten-robolab"
os.chdir(ROOT)
JOBS = "scratchpad/tt/jobs.jsonl"
while True:
    if os.path.exists("scratchpad/tt/qd.stop"):
        break
    todo = None
    if os.path.exists(JOBS):
        for line in open(JOBS):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            j = json.loads(line)
            lg = f"out/tt_r10/{j['tag']}.log"
            done = os.path.exists(lg) and any(l.startswith("{") for l in open(lg))
            if not done and not j.get("skip"):
                todo = j
                break
    if todo is None:
        time.sleep(5)
        continue
    # only one tt_eval at a time (3 workers): wait for any other of my runs (batch scripts) to finish
    if subprocess.run(["pgrep", "-f", "playground/tt_eval.py"], capture_output=True).stdout.strip():
        time.sleep(5)
        continue
    j = todo
    env = dict(os.environ, TT_ENV="P2")
    if j.get("log", True):
        env["TT_SAVE_LOG"] = f"{ROOT}/out/tt_r10/{j['tag']}_logs"
    env.update({k: str(v) for k, v in j.get("env", {}).items()})
    cmd = [".venv-myo/bin/python", "playground/tt_eval.py", "--params", j["params"], "--controller", j["ctl"],
           "--seeds", j["seeds"], "--out", f"out/tt_r10/{j['tag']}.jsonl", "--workers", "3"]
    if j.get("set"):
        cmd += ["--set", j["set"]]
    with open(f"out/tt_r10/{j['tag']}.log", "w") as lg:
        p = subprocess.Popen(cmd, stdout=lg, stderr=subprocess.STDOUT, env=env)
        open("scratchpad/tt/qd.current", "w").write(f"{j['tag']} pid {p.pid} started {time.strftime('%H:%M:%S')}\n")
        p.wait()
    time.sleep(1)
