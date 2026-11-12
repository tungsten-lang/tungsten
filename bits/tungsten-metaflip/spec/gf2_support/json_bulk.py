#!/usr/bin/env python3
"""Python side of json_bulk.w: sha256 of json.dumps(json.loads(file)) per file, plus timings."""
import hashlib
import json
import sys
import time

parse_time = dump_time = 0.0
size = files = 0
for path in open(sys.argv[1]).read().split('\n'):
    if not path:
        continue
    raw = open(path, 'rb').read()
    t0 = time.perf_counter()
    tree = json.loads(raw)
    t1 = time.perf_counter()
    text = json.dumps(tree)
    t2 = time.perf_counter()
    print(hashlib.sha256(text.encode()).hexdigest() + '\t' + path)
    parse_time += t1 - t0
    dump_time += t2 - t1
    size += len(raw)
    files += 1
print(f'# {files} files, {size} bytes, parse {parse_time:.3f} s, dump {dump_time:.3f} s')
