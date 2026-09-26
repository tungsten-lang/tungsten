#!/usr/bin/env python3
"""Matched fixed-work replay: canonical endpoints, counters, RNG, and full tensors."""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import tempfile

from packed_composition_parity_test import exact, naive
from wide_matrix_cleanup_parity_test import blob, read_blob


def run(binary, source, steps, mode, seed, prefix, audit):
    proc = subprocess.run([str(binary), str(source), str(steps), str(mode), str(seed),
                           str(prefix), str(int(audit))], check=True, capture_output=True,
                          text=True, timeout=120)
    assert proc.stdout.startswith('REPLAY '), proc.stdout
    fields = dict(item.split('=', 1) for item in proc.stdout.split()[1:])
    result = {k: int(v) if k not in ('current', 'best') else v for k, v in fields.items()}
    assert result['moves'] == steps
    assert result['accepts'] + result['rejects'] == steps
    outputs = {}
    for kind in ('current', 'best'):
        path = prefix.with_name(prefix.name + '-' + kind + '.mfw')
        outputs[kind] = path.read_bytes()
        shape, terms = read_blob(outputs[kind])
        assert len(terms) == result[kind + '_rank']
        exact(shape, terms)
    return result, outputs


def check(before, after, output, benchmark_source=None):
    package = Path(__file__).resolve().parents[1]
    output.mkdir(parents=True, exist_ok=False)
    rows = []
    with tempfile.TemporaryDirectory(prefix='metaflip-directed-replay-') as temp:
        root = Path(temp)
        cases = []
        for n in range(8, 17):
            source = sorted((package / 'lib/metaflip/seeds/gf2/wide').glob(f'matmul_{n}x{n}_rank*.mfw'))[0]
            cases.append(source)
        # Sparse source, many equal factors/cancellations, asymmetric limbs,
        # and the maximum 1024-bit factor width all use the same live engine.
        for shape in ((2, 2, 2), (3, 5, 7), (2, 2, 512)):
            source = root / ('x'.join(map(str, shape)) + '.mfw')
            source.write_bytes(blob(shape, naive(shape)))
            cases.append(source)
        if benchmark_source:
            cases.append(benchmark_source)
        for index, source in enumerate(cases):
            for mode in (1, 2, 3):
                steps = 20000
                seed = 19071 + index
                old, old_outputs = run(before, source, steps, mode, seed,
                                       root / 'before', True)
                new, new_outputs = run(after, source, steps, mode, seed,
                                       root / 'after', True)
                assert {k: v for k, v in old.items() if k != 'ms'} == {k: v for k, v in new.items() if k != 'ms'}, (source, mode, old, new)
                assert old_outputs == new_outputs, (source, mode)
                rows.append(dict(source=str(source), mode=mode, seed=seed,
                                 steps=steps, before=old, after=new))
            print('PASS exact replay', source.name, 'all 3 modes', flush=True)
        if benchmark_source:
            timings = {'before': [], 'after': []}
            for repeat, order in enumerate((('before', 'after'), ('after', 'before'),
                                            ('before', 'after'))):
                seen = {}
                for label in order:
                    result, outputs = run(before if label == 'before' else after,
                                          benchmark_source, 10000000, 2, 25000010,
                                          root / label, False)
                    timings[label].append(result['ms'])
                    seen[label] = ({k: v for k, v in result.items() if k != 'ms'}, outputs)
                    print('BENCH', label, result['ms'], 'ms', flush=True)
                assert seen['before'] == seen['after']
            medians = {k: statistics.median(v) for k, v in timings.items()}
            rows.append(dict(benchmark=str(benchmark_source), steps=10000000,
                             mode=2, timings_ms=timings, median_ms=medians,
                             speedup=medians['before'] / medians['after']))
            print('MATCHED', json.dumps(rows[-1]), flush=True)
    (output / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--benchmark-source', type=Path)
    args = parser.parse_args()
    check(args.before.resolve(), args.after.resolve(), args.output.resolve(),
          args.benchmark_source.resolve() if args.benchmark_source else None)
