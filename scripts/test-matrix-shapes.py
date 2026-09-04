#!/usr/bin/env python3
"""Capture pre-guard binaries, then compare the exact fixture after guards."""
import json
from pathlib import Path
import statistics
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/reports/matrix-shapes'
OUT.mkdir(parents=True, exist_ok=True)

def run(*args):
 p=subprocess.run([str(a) for a in args],cwd=ROOT,text=True,capture_output=True,timeout=90)
 assert p.returncode==0,p.stdout+p.stderr
 return p.stdout

capture='--capture' in sys.argv
for n in (2,3,4):
 source=OUT/f'fixture{n}.w'
 source.write_text(f'''a = Mat{n}<f64>.identity
b = Mat{n}<f64>.identity
i = 0
start = clock()
while i < 50000
  a.elements[0] = (i % 7).to_f()
  out = a + b
  i += 1
elapsed = clock() - start
if out.elements[0] != ~6.0
  raise "checksum"
<< elapsed
''')
 run(ROOT/'bin/tungsten-compiler','compile',source,'--out',OUT/f'{"before" if capture else "after"}{n}','--release','--no-lto')
if capture:
 print('Captured pre-guard fixtures');sys.exit(0)
results={}
for n in (2,3,4):
 source=OUT/f'invalid{n}.w'
 source.write_text(f'''rejected = 0
counts = [0, {n*n-1}, {n*n+1}]
i = 0
while i < counts.size()
  count = counts[i]
  i += 1
  begin
    Mat{n}<f64>.new(f64[count])
  rescue error
    if error.to_s.include?("requires {n*n} elements")
      rejected += 1
if rejected != 3
  raise "wrong-length input accepted"
valid = Mat{n}<f64>.new(f64[{n*n}])
if valid.elements.size() != {n*n}
  raise "valid shape rejected"
<< "PASS"
''')
 run(ROOT/'bin/tungsten-compiler','compile',source,'--out',OUT/f'invalid{n}','--no-lto')
 assert 'PASS' in run(OUT/f'invalid{n}')
 pairs=[]
 for i in range(6):
  pair={}
  for mode in (('before','after') if i%2==0 else ('after','before')):
   pair[mode]=float(run(OUT/f'{mode}{n}').strip())
  pairs.append(pair)
 results[str(n)]={'pairs_seconds':pairs,'median_seconds':{m:statistics.median(p[m] for p in pairs) for m in ('before','after')}}
(OUT/'result.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
print('PASS: short/long/empty constructor rejection and valid construction')
