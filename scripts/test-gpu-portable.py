#!/usr/bin/env python3
import json
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/reports/gpu-portable';OUT.mkdir(parents=True,exist_ok=True)
fixtures={
 'good':'''## f32[]: a
## f32[]: b
## i32: n
@gpu fn add_one(a, b, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n
    b[i] = a[i] + 1.0
''',
 'metal_only':'''## f32[]: input
@gpu fn metal_only(input)
  simdgroup_load(0, input, 0, 8)
''',
 'too_large':'''## f32[]: output
@gpu fn too_large(output)
  tile = gpu.shared_f32(5000)
  tile[0] = 1.0
  output[0] = tile[0]
''',
 'no_kernel':'<< "@gpu fn fake()"\n'}
for name,text in fixtures.items():
 source=OUT/(name+'.w');source.write_text(text)
 p=subprocess.run([str(ROOT/'bin/tungsten'),'gpu-check','--json',str(source)],cwd=ROOT,text=True,capture_output=True,timeout=60)
 report=json.loads(p.stdout)
 assert report['accepted']==(name=='good'),report
 assert p.returncode==(0 if name=='good' else 1),report
 for suffix in ('.metal','.cu','.wgsl'):
  assert not source.with_suffix(suffix).exists(),'check wrote a sidecar'
 (OUT/(name+'.json')).write_text(p.stdout)
print('PASS: shared kernel, Metal-only rejection, portable shared-memory limit, no-kernel rejection; no sidecars or execution')
