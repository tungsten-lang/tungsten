#!/usr/bin/env python3
"""Report when a subagent has written nothing to its transcript for N minutes of AWAKE time.

    python3 tools/agent_watchdog.py AGENT_ID [MINUTES=25]     (run it as a background command; it exits with one line when the agent goes silent)

A laptop that suspends (lid closed, idle sleep) freezes the agent and every job with it, and the wall clock jumps by hours on wake: a watchdog that compares `date` with the
transcript's mtime then reports a stall that never happened (it did, twice, on 3 Oct 2026). time.monotonic() does not advance while the machine sleeps on macOS, so silence is
measured in awake time only: the clock starts again from the moment the transcript last changed, as seen by this process.
"""
import glob
import os
import sys
import time

agent = sys.argv[1]
limit = 60.0 * float(sys.argv[2] if len(sys.argv) > 2 else 25)
hits = glob.glob(os.path.expanduser(f"~/.claude/projects/*/*/subagents/agent-{agent}.jsonl"))
if not hits:
    sys.exit(f"no transcript found for agent {agent}")
f = hits[0]
last = os.path.getmtime(f)
t_last = time.monotonic()
while True:
    time.sleep(30)
    m = os.path.getmtime(f)
    if m != last:
        last, t_last = m, time.monotonic()
    elif time.monotonic() - t_last > limit:
        print(f"agent {agent} has written nothing for {(time.monotonic() - t_last) / 60:.0f} awake minutes (now {time.strftime('%H:%M:%S')}): stalled or finished; check its LOG.md and relaunch with the same one-line prompt if it did not finish")
        break
