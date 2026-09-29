#!/usr/bin/env python3
"""Check packed native helpers allocate no per-word BigInts (not a timing gate)."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, help='Use an already compiled packed_allocations_probe.w')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    with tempfile.TemporaryDirectory(prefix='wassat-packed-alloc-') as temp:
        binary = args.binary.resolve() if args.binary else Path(temp) / 'probe'
        if not args.binary:
            subprocess.run([str(root / 'bin/tungsten'), 'compile',
                            str(Path(__file__).with_name('packed_allocations_probe.w')),
                            '--release', '--native', '-o', str(binary)],
                           cwd=root, check=True, timeout=600)
        result = subprocess.run([str(binary)], env=dict(os.environ, TUNGSTEN_ALLOC_PROFILE='1'),
                                capture_output=True, text=True, check=True, timeout=30)
        assert 'packed allocation probe complete' in result.stdout, result.stdout
        count = re.search(r'^TALLOC bigint_arena\s+(\d+)\s+(\d+)', result.stderr, re.M)
        assert count, result.stderr
        # Startup can allocate a few BigInts; 100,000 packed iterations must not.
        assert int(count[1]) <= 32, result.stderr
        print(f'PASS: 100000 packed iterations; {count[1]} BigInt allocations')


if __name__ == '__main__':
    main()
