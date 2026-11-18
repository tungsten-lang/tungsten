#!/usr/bin/env python3
"""Run one interpreted Satori spec at a time, including across runner invocations."""

import fcntl
import os
from pathlib import Path
import re
import signal
import sys


root = Path(__file__).resolve().parents[1]
if len(sys.argv) != 2 or sys.argv[1].startswith("-"):
    sys.exit("usage: run-satori-spec.py SPEC.w")
limit = os.environ.get("SATORI_TEST_MEMORY_MB", "2048")
if not re.fullmatch(r"[0-9]{1,4}", limit) or not 1 <= int(limit) <= 4096:
    sys.exit("SATORI_TEST_MEMORY_MB must be 1..4096 MiB")
if not os.access(root / "bin/tungsten-compiler", os.X_OK):
    sys.exit("build the native interpreter before running Satori specs")

# Keep the descriptor through both execs, so killing the runner cannot leave
# an unlocked interpreter. Never unlink the inode while another runner waits.
fd = os.open(f"/tmp/tungsten-satori-spec-{os.getuid()}.lock",
             os.O_CREAT | os.O_RDONLY | os.O_NOFOLLOW, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
os.set_inheritable(fd, True)
signal.alarm(int(os.environ.get("BIT_SPEC_TIMEOUT_SECONDS", "300")))
# Preserve a stricter inherited watchdog, including fractional and sub-MiB
# settings. An unset, disabled or malformed value still gets the runner cap.
inherited = os.environ.get("TUNGSTEN_MEMORY_LIMIT", "")
setting = re.fullmatch(r"\s*\+?((?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:e[+-]?[0-9]+)?)([KMGT]?)(?:i?b)?",
                       inherited, re.I)
watchdog = f"{limit}M"
if setting:
    unit = setting[2].upper() or "M"
    mib = float(setting[1]) * {"K": 1 / 1024, "M": 1, "G": 1024, "T": 1024**2}[unit]
    if 1 / 1024**2 <= mib < int(limit):
        watchdog = setting[1] + unit
os.environ["TUNGSTEN_MEMORY_LIMIT"] = watchdog
tungsten = os.environ.get("TUNGSTEN", str(root / "bin/tungsten"))
os.execvp(tungsten, [tungsten, "run", "--interpret", sys.argv[1]])
