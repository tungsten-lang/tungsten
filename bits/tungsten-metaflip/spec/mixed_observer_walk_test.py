#!/usr/bin/env python3
"""Read-only mixed observers: independent every-observation minima and replay."""
from itertools import permutations
from pathlib import Path
import subprocess
import sys
import tempfile

from mixed_composition_parity_test import components, optimal
from packed_composition_parity_test import exact, naive


def fields(text, label):
    return [dict(word.split('=', 1) for word in line.split()[1:])
            for line in text.splitlines() if line.startswith(label+' ')]


def read_scheme(path, shape):
    lines = path.read_text().splitlines()
    terms = [tuple(map(int, line.split())) for line in lines[1:]]
    assert int(lines[0]) == len(terms)
    exact(shape, terms)
    return terms


def greedy_price(terms, costs):
    """Independent six-order fallback, on canonical BFS component ordering."""
    terms = sorted(terms)
    unseen = set(range(len(terms)))
    answer = len(terms)*costs[0]
    while unseen:
        group = [min(unseen)]
        unseen.remove(group[0])
        for i in group:
            more = [j for j in sorted(unseen) if any(
                terms[i][a] == terms[j][a] and costs[a+1] < 2*costs[0]
                for a in range(3))]
            group.extend(more)
            unseen.difference_update(more)
        best = 0
        for order in permutations(range(3)):
            used = set()
            saving = 0
            for axis in order:
                gain = 2*costs[0]-costs[axis+1]
                if gain <= 0:
                    continue
                for pos, i in enumerate(group):
                    if i in used:
                        continue
                    for j in group[pos+1:]:
                        if j not in used and terms[i][axis] == terms[j][axis]:
                            used.update((i, j))
                            saving += gain
                            break
            best = max(best, saving)
        answer -= best
    return answer


def check(binary):
    with tempfile.TemporaryDirectory(prefix='metaflip-mixed-observer-') as temporary:
        root = Path(temporary)
        shape = (2, 2, 2)
        terms = naive(shape)
        source = root/'parent.txt'
        source.write_text(str(len(terms))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in terms))
        tables = [[11, 21, 20, 20], [15, 30, 29, 29], [20, 40, 38, 40],
                  [23, 44, 44, 44], [29, 58, 54, 54], [38, 74, 73, 74],
                  [20, 21, 22, 23], [7, 14, 14, 14]]

        def run(name, rows, steps=32, budget=50000, shape=shape, source=source,
                mode='walk', extra=(), limit=10, raw=None, success=True):
            directory = root/name
            directory.mkdir()
            primary = [[23*k-(5*(k//3) if a == 1 else 0) for k in range(limit+1)]
                       for a in range(3)]
            lines = [str(limit), *(' '.join(map(str,r)) for r in primary)]
            if rows:
                lines += [f'mixed-observers {len(rows)} {budget}',
                          *(' '.join(map(str,r)) for r in rows)]
            table = directory/'prices.txt'
            table.write_text(raw if raw is not None else '\n'.join(lines)+'\n')
            command = [binary, str(source), 'x'.join(map(str,shape)), str(table),
                       '1', '1', str(steps), mode, '930917', str(directory), '2', '4', '1', *extra]
            result = subprocess.run(command, capture_output=True, text=True, timeout=60)
            assert (result.returncode == 0) == success, (command, result.stdout, result.stderr)
            if not success:
                assert not list(directory.glob('*trial-*.txt'))
            return directory, result.stdout

        control, control_text = run('control', [])
        together, text = run('together', tables)
        assert fields(control_text, 'BUD_TRIAL') == fields(text, 'BUD_TRIAL')
        for key in ('attempted', 'accepted_flips', 'accepted_chunks', 'observations'):
            assert fields(control_text,'BUD_RESULT')[0][key] == fields(text,'BUD_RESULT')[0][key]
        assert (control/'trial-0.txt').read_bytes() == (together/'trial-0.txt').read_bytes()
        assert (control/'end-0.txt').read_bytes() == (together/'end-0.txt').read_bytes()
        assert not fields(text,'BUD_OBSERVER')
        stats = fields(text,'BUD_MIXED')[0]
        assert int(stats['evaluations']) == 8*33 and int(stats['fallback_components']) == 0
        # One chunk has the same RNG for every prefix length. Rebuild EVERY
        # observed state independently instead of only checking retained scores.
        samples = [terms]
        for length in range(1, 33):
            directory, _ = run('prefix-'+str(length), [], steps=length)
            samples.append(read_scheme(directory/'end-0.txt', shape))
        for index, costs in enumerate(tables):
            objectives = [(optimal(sorted(t),costs), len(t), sum(v.bit_count() for row in t for v in row))
                          for t in samples]
            at = min(range(len(samples)), key=lambda i: objectives[i])
            row = fields(text,'BUD_MIXED_OBSERVER')[index]
            assert tuple(int(row[k]) for k in ('score','rank','bits')) == objectives[at]
            assert int(row['best_at']) == at
            got = read_scheme(together/f'mixed-observer-{index}-trial-0.txt',shape)
            assert sorted(got) == sorted(samples[at])
            alone, alone_text = run('alone-'+str(index), [costs])
            assert fields(alone_text,'BUD_MIXED_OBSERVER')[0] | {'observer':str(index)} == row
            assert (alone/'mixed-observer-0-trial-0.txt').read_bytes() == (together/f'mixed-observer-{index}-trial-0.txt').read_bytes()
        print('PASS mixed observers: 8 objectives, 33 independent states, identical primary/endpoints and flip accounting',flush=True)

        # Budget exhaustion and >16-vertex components remain honest fallback
        # scores. They are not silently treated as exact minima.
        for shape in ((2,2,2),(3,3,3),(5,5,5)):
            t = naive(shape)
            source = root/('parent-'+'x'.join(map(str,shape))+'.txt')
            source.write_text(str(len(t))+'\n'+''.join(' '.join(map(str,row))+'\n' for row in t))
            costs = [20,21,22,23]
            directory, output = run('fallback-'+'x'.join(map(str,shape)), [costs], steps=8,
                                    budget=1, shape=shape, source=source, limit=len(t)+2)
            got = read_scheme(directory/'mixed-observer-0-trial-0.txt',shape)
            assert int(fields(output,'BUD_MIXED_OBSERVER')[0]['score']) == greedy_price(got,costs)
            assert int(fields(output,'BUD_MIXED')[0]['fallback_components']) > 0
        print('PASS mixed observers: bounded fallback, canonical replay and rank-above-64 state',flush=True)

        primary = (together/'prices.txt').read_text().splitlines()[:4]
        bad = [primary+['mixed-observers 0 50000','7 11 11 11'],
               primary+['mixed-observers 9 50000']+['7 11 11 11']*9,
               primary+['mixed-observers 1 0','7 11 11 11'],
               primary+['mixed-observers 1 1000001','7 11 11 11'],
               primary+['mixed-observers 01 50000','7 11 11 11'],
               primary+['mixed-observers 1 050000','7 11 11 11'],
               primary+['mixed-observers 2 50000','7 11 11 11'],
               *[primary+['mixed-observers 1 50000',row] for row in
                 ('7 11 11','7 11 11 11 11','0 11 11 11','129 11 11 11','7 -1 11 11','7 01 11 11')]]
        for i, rows in enumerate(bad):
            _, output = run('bad-'+str(i), [], raw='\n'.join(rows)+'\n', success=False)
            assert 'invalid mixed observer' in output
        run('bad-mode', tables, mode='greedy', success=False)
        run('bad-holdout', tables, extra=('missing-holdout',), success=False)
        run('bad-limit', tables, limit=513, success=False)
        print(f'PASS mixed observers: {len(bad)+3} malformed/incompatible calls reject without candidate export',flush=True)


if __name__ == '__main__':
    check(sys.argv[1])
