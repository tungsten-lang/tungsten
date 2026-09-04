#!/usr/bin/env python3
"""Numerical, alias and whole-loop timings for fixed-size output methods."""
import json
from pathlib import Path
import statistics
import subprocess
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/reports/small-matrix'
OUT.mkdir(parents=True, exist_ok=True)

def run(*args):
    p = subprocess.run([str(a) for a in args], cwd=ROOT, text=True, capture_output=True, timeout=90)
    assert p.returncode == 0, p.stdout + p.stderr
    assert 'FAIL' not in p.stdout, p.stdout
    return p.stdout

results = {}
for n in (2, 3, 4):
    prefix = f'''a = Mat{n}<f64>.identity
b = Mat{n}<f64>.identity
out = Mat{n}<f64>.zero
'''
    source = prefix + '''ret = a.add_into(b, out)
if runtime_identity(ret) != runtime_identity(out)
  raise "return is not destination"
if out.elements[0] != ~2.0 || a.elements[0] != ~1.0 || b.elements[0] != ~1.0
  raise "add result or source preservation"
a.add_into(b, a)
if a.elements[0] != ~2.0
  raise "exact alias add"
a.sub_into(b, a)
if a.elements[0] != ~1.0
  raise "exact alias subtract"
i = 0
while i < a.elements.size()
  a.elements[i] = (i + 1).to_f()
  b.elements[i] = (i % 3 - 1).to_f()
  i += 1
product = a * b
a.mul_into(b, out)
i = 0
while i < out.elements.size()
  if out.elements[i] != product.elements[i]
    raise "product differs"
  i += 1
a.elements[0] = ~1.0
b.elements[0] = ~1.0
fresh = a + b
out.elements[0] = ~99.0
if fresh.elements[0] != ~2.0 || a.elements[0] != ~1.0
  raise "value semantics changed"
<< "PASS"
'''
    check = OUT / f'check{n}.w'
    check.write_text(source)
    run(ROOT / 'bin/tungsten-compiler', 'compile', check, '--out', OUT / f'check{n}', '--no-lto')
    run(OUT / f'check{n}')
    for mode in ('operator', 'into'):
        expression = 'out = a + b' if mode == 'operator' else 'a.add_into(b, out)'
        source = prefix + f'''i = 0
start = clock()
while i < 50000
  a.elements[0] = (i % 7).to_f()
  {expression}
  i += 1
elapsed = clock() - start
if out.elements[0] != ~6.0
  raise "benchmark checksum"
<< elapsed
'''
        fixture = OUT / f'{mode}{n}.w'
        fixture.write_text(source)
        run(ROOT / 'bin/tungsten-compiler', 'compile', fixture, '--out', OUT / f'{mode}{n}', '--release', '--no-lto')
    pairs = []
    for repeat in range(6):
        pair = {}
        for mode in (('operator', 'into') if repeat % 2 == 0 else ('into', 'operator')):
            pair[mode] = float(run(OUT / f'{mode}{n}').strip())
        pairs.append(pair)
    results[str(n)] = {'pairs_seconds': pairs, 'median_seconds': {
        mode: statistics.median(p[mode] for p in pairs) for mode in ('operator', 'into')}}
(OUT / 'result.json').write_text(json.dumps(results, indent=2) + '\n')
print(json.dumps(results, indent=2))
print('PASS: Mat2/3/4 values, exact alias, independent operators and six alternating timing pairs')
