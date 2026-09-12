#!/usr/bin/env python3
"""Recover two exact historical witnesses into local state, never the package.

Coefficient redistribution provenance remains under review. This reads only
the user's existing Git objects, does not fetch archives, and never replaces
an existing checkpoint (including a malformed or higher-rank checkpoint).
"""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from import_wide_seeds import blob, verify

COMMIT = 'a0c14c3b08ea0a0a07745b0fc530266cd317e091'
RECORDS = (
    (13, 1402, 'f97d8d69de4881a13704901925ef16ec4aac2feb24fb94aed59fce2f391da1d4'),
    (15, 2008, '5e280713e67699810ebc72ea1a5871df419cf4d802322c9862c7c9969fb6d0af'),
)


def normalize(raw, n, rank, digest):
    if hashlib.sha256(raw).hexdigest() != digest:
        raise ValueError('historical witness digest mismatch')
    terms = []
    for line in raw.decode('ascii').splitlines():
        if not re.fullmatch(r'R [0-9]+ [0-9]+ [0-9]+', line):
            raise ValueError('malformed historical term')
        terms.append(tuple(map(int, line.split()[1:])))
    counts = Counter(terms)
    terms = sorted(term for term, count in counts.items() if count % 2)
    if len(terms) != rank:
        raise ValueError('historical rank mismatch')
    verify(n, terms)
    return blob(n, terms)


def publish_new(path, body):
    """Atomic no-clobber publication, including concurrent checkpoint writers."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.recover-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as output:
            output.write(body)
            output.flush()
            os.fsync(output.fileno())
        try:
            os.link(name, path)
        except FileExistsError:
            return False
        return True
    finally:
        os.unlink(name)


def run(repo, state):
    for n, rank, digest in RECORDS:
        source = f'benchmarks/matmul/metaflip/matmul_{n}x{n}_rank{rank}_block47_gf2.txt'
        raw = subprocess.check_output(['git', '-C', str(repo), 'show', f'{COMMIT}:{source}'])
        body = normalize(raw, n, rank, digest)
        target = state / f'checkpoints/gf2/{n}x{n}x{n}/best.txt'
        if not publish_new(target, body):
            print(f'PRESERVED existing {target}')
            continue
        record = dict(commit=COMMIT, source=source, source_sha256=digest,
                      certificate_sha256=hashlib.sha256(body).hexdigest(),
                      square=n, rank=rank, field='GF(2)', exact=True,
                      redistribution='Local historical witness; not bundled; review pending')
        publish_new(target.with_name('recovered-seed-provenance.json'),
                    (json.dumps(record, indent=2)+'\n').encode())
        print(f'RECOVERED EXACT {n}x{n} rank={rank}: {target}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--state-dir', type=Path, default=Path.home()/'.tungsten/metaflip')
    args = parser.parse_args()
    run(args.repo, args.state_dir)
