#!/usr/bin/env python3
"""Python side of json_bench.w: json.loads / json.dumps on the catalogue, repr of the golden doubles."""
import json
import statistics
import struct
import sys
import time


def median_time(fn, runs=5):
    times = []
    for _ in range(runs):
        t0 = time.perf_counter()
        fn()
        times.append(time.perf_counter() - t0)
    return statistics.median(times)


raw = open(sys.argv[1], 'rb').read()
print('json.loads catalog          %.4f' % median_time(lambda: json.loads(raw)))
tree = json.loads(raw)
print('json.dumps indent=1 catalog %.4f' % median_time(lambda: json.dumps(tree, indent=1)))
print('json.dumps default catalog  %.4f' % median_time(lambda: json.dumps(tree)))
floats = [struct.unpack('<d', bytes.fromhex(line.split('\t')[0])[::-1])[0] for line in open(sys.argv[2]) if line.strip()]
print('repr %d doubles          %.4f' % (len(floats), median_time(lambda: [repr(x) for x in floats])))
