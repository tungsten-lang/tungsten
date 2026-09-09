#!/usr/bin/env python3
"""Short public-binary resource canary, not a throughput benchmark."""
from pathlib import Path
import json
import os
import sys
import tempfile
import threading

from refinement_fleet_test import run


def check(binary, seconds=15):
    os.environ['METAFLIP_COMPOSITION_PENDING'] = '1269'
    os.environ['METAFLIP_COMPOSITION_FIFO'] = '0'
    samples = []; stopped = threading.Event()
    with tempfile.TemporaryDirectory(prefix='metaflip-pressure-canary-') as d:
        root = Path(d)/'run'; spool = root/'status.txt.refinement'

        def monitor():
            while not stopped.wait(0.05):
                def counter(name):
                    try:
                        return int((spool/'composition'/name).read_text())
                    except FileNotFoundError:
                        return 0
                submitted = counter('submitted'); completed = counter('consumed')
                samples.append((max(0,submitted-completed),(spool/'backpressure').exists()))

        thread = threading.Thread(target=monitor); thread.start()
        try:
            result = run(binary,root,'5x5',1,seconds=seconds)
        finally:
            stopped.set(); thread.join()
        peak = max((pending for pending,_ in samples),default=0)
        assert peak <= 1269, peak
        assert result['compose_limit'] == '1269'
        files = [p for p in spool.rglob('*') if p.is_file()]
        print(json.dumps(dict(seconds=seconds,workers=1,gpu=False,
             samples=len(samples),sampled_pending_peak=peak,
             observed_backpressure=any(blocked for _,blocked in samples),
             refinement_pending=int(result['refine_pending']),
             composition_completed=int(result['compose_completed']),
             composition_pending=int(result['compose_pending']),
             moves=int(result['moves']),files=len(files),
             logical_bytes=sum(p.stat().st_size for p in files)),sort_keys=True))


if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve())
