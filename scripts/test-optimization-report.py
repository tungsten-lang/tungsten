#!/usr/bin/env python3
"""Exercise inspection, source provenance, and normal-emission parity."""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/reports/optimization-report'
OUT.mkdir(parents=True, exist_ok=True)
source = OUT / 'fixture.w'
sentinel = OUT / 'must-not-execute'
sentinel.unlink(missing_ok=True)
source.write_text('''+ Box
  -> new(@value)
  -> size()
    @value

-> unknown(obj)
  obj.size()

-> convert(values)
  values ## f64[]

-> typed(a, b) (i64 i64) i64
  a + b

box = Box.new(3)
<< box.size()
write_file("''' + str(sentinel) + '''", "executed")
''')

def run(*args, env=None):
    p = subprocess.run([str(a) for a in args], cwd=ROOT, text=True,
                       capture_output=True, timeout=60, env=env)
    assert p.returncode == 0, p.stdout + p.stderr
    return p.stdout

for verbosity in ([], ['--verbose'], ['-v']):
    report = json.loads(run(ROOT / 'bin/tungsten', '--optimizations-json', *verbosity, source))
    assert report['schema_version'] == 1
    assert report['phase'] == 'lowered_wire_before_mid_end'
    rows = report['sites']
    assert all(Path(r['file']).resolve() == source for r in rows)
    assert any(r['function'] == 'unknown' and r['category'] == 'dynamic_dispatch'
               and r['target'] == 'size' and r['line'] == 7 for r in rows), rows
    assert any(r['category'] == 'guarded_dispatch' and r['target'] == 'size' for r in rows)
    assert any(r['function'] == 'convert' and r['category'] == 'array_conversion' for r in rows)
    assert not any(r['function'] == 'typed' and r['category'] == 'generic_arithmetic' for r in rows)
    assert not sentinel.exists(), 'inspection executed source code'
text = run(ROOT / 'bin/tungsten', '--optimizations', source)
assert 'Static sites are not measured hotspots' in text and 'dynamic_dispatch' in text
for label, compiler in [('before', ROOT / 'build/reports/compiler-baseline'),
                        ('after', ROOT / 'bin/tungsten-compiler')]:
    run(compiler, 'compile', source, '--out', OUT / label, '--emit-ll', '--no-lto',
        env={**os.environ, 'TUNGSTEN_LL_PATH': str(OUT / (label + '.ll'))})
assert (OUT / 'before.ll').read_bytes() == (OUT / 'after.ll').read_bytes()
assert (OUT / 'before.sidemap').read_bytes() == (OUT / 'after.sidemap').read_bytes()
assert not sentinel.exists()
(OUT / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS: inspection facts, JSON verbosity, no execution, LLVM/sidemap baseline identity')
