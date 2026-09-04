#!/usr/bin/env python3
"""Verify summaries against runtime-produced words in a real LLDB session."""
from pathlib import Path
import json
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/reports/lldb-values'
OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'fixture.c').write_text('''#include "runtime/runtime.h"
#include <stdlib.h>
WValue negative, small, floating, array;
__attribute__((noinline)) void ready(void) { __asm__ volatile("" ::: "memory"); }
int main(void) {
 negative = w_box_int(-42); small = w_box_inline_str("hi", 2); floating = w_box_double(3.5);
 WArray *a = aligned_alloc(16, 32); *a = (WArray){.ebits=-64, .size=3, .cap=3};
 array = w_box_array(a); ready(); free(a); return 0;
}
''')
p = subprocess.run(['clang', '-g', '-O0', '-I', str(ROOT), str(OUT / 'fixture.c'),
                    '-o', str(OUT / 'fixture')], capture_output=True, text=True)
assert p.returncode == 0, p.stderr
(OUT / 'fixture.sidemap').write_text(json.dumps({'version': 1, 'hashes': {'test': {'symbol': 'ready', 'originals': [{'symbol': 'ready', 'file': 'fixture.w', 'line': 4, 'class': 'Probe', 'method': 'ready'}]}}}))
script = ROOT / 'scripts/debug/tungsten_lldb.py'
commands = [f'command script import "{script}"', 'wbreak fixture.w:4', 'run', 'wsource',
            'target variable negative small floating array', 'wvalue 0xfffaffffffffffd6',
            'wvalue 0xfff4000000001000']
argv = ['lldb', '--batch']
for command in commands:
    argv += ['-o', command]
argv += ['--', str(OUT / 'fixture')]
p = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, timeout=30)
(OUT / 'lldb.log').write_text(p.stdout + p.stderr)
assert p.returncode == 1 and "unreadable target memory" in p.stderr, p.stdout + p.stderr
for fragment in ('fixture.w:4  ready', 'negative =', '-42', '"hi"', '3.5', 'Array size=3 ebits=-64', 'unreadable target memory'):
    assert fragment in p.stdout + p.stderr, p.stdout + p.stderr
print('PASS: actual LLDB, runtime words, bounded unreadable-memory behavior')
