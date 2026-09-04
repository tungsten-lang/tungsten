#!/usr/bin/env python3
"""Check the existing GPU emitters' shared subset without executing a program."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from lib.tungsten_ast import read, walk
ROOT = Path(__file__).resolve().parents[1]
PROFILE = {'schema_version': 1, 'profile': 'metal-cuda-wgsl-v1',
           'dialects': ['metal', 'cuda', 'wgsl'], 'shared_storage_limit_bytes': 16384,
           'validation': 'Tungsten compiler preflight and dialect emission',
           'external_shader_compilation': False, 'device_execution': False,
           'limitations': ['Dynamic bounds, race freedom and numerical equivalence are not proved.',
                           'Device availability and optional features require host checks.']}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path, nargs='?')
parser.add_argument('--json', action='store_true')
parser.add_argument('--capabilities', action='store_true')
args = parser.parse_args()
if args.capabilities:
    print(json.dumps(PROFILE, indent=2)); raise SystemExit(0)
if args.source is None: parser.error('source is required')
source = args.source.resolve()
report = {**PROFILE, 'source': str(source), 'accepted': False}
try:
    report['source_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
    ast = read(ROOT / 'bin/tungsten-compiler', source)
    report['entry_kernels'] = [n['name'] for n in walk(ast) if n.get('node') == 'gpu_kernel_def']
    if not report['entry_kernels']:
        raise ValueError('source contains no entry GPU kernel definitions')
    result = subprocess.run([str(ROOT/'bin/tungsten-compiler'), '--check', str(source)],
                            env={**os.environ, 'TUNGSTEN_GPU_DIALECTS':'metal,cuda,wgsl'},
                            text=True, capture_output=True, timeout=60)
    report['accepted'] = result.returncode == 0
    report['diagnostics'] = result.stdout + result.stderr
except (OSError, ValueError, subprocess.TimeoutExpired) as error:
    report['diagnostics'] = str(error)
if args.json:
    print(json.dumps(report, indent=2))
else:
    print(('PASS' if report['accepted'] else 'FAIL') + ': ' + PROFILE['profile'])
    print(report.get('diagnostics', '').strip())
    print('Compiler preflight only; device execution and external shader validation are separate.')
raise SystemExit(0 if report['accepted'] else 1)
