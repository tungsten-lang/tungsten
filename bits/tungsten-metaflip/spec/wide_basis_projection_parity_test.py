#!/usr/bin/env python3
"""Independent wide neutral-basis and bit-grid projection checks."""
from pathlib import Path
from hashlib import sha256
from itertools import product
import argparse
import json
import random
import subprocess
import tempfile

from wide_matrix_cleanup_parity_test import blob, read_blob, same_tensor
from packed_composition_parity_test import exact, naive
from verify_cofactor_mergers import refactor_shared
from verify_coordinate_projections import project_grid


def check(basis, projection, report=None):
    basis, projection = map(lambda p: str(Path(p).resolve()), (basis, projection))
    for binary, label in ((basis, 'PASS wide matrix'), (projection, 'PASS wide projection')):
        r = subprocess.run([binary], capture_output=True, text=True, timeout=60, check=True)
        assert label in r.stdout, r.stdout
    rng = random.Random(104219)
    counts = dict(basis_inputs=0, basis_runs=0, limited=0, neutral_changes=0,
                  projections=0, projected_full_tensors=0)
    with tempfile.TemporaryDirectory(prefix='metaflip-wide-transforms-') as directory:
        root = Path(directory)
        source, target = root/'source.tensor', root/'target.tensor'
        for trial in range(36):
            width = (31, 32, 33, 63, 64, 65, 127, 256, 511, 756, 1023, 1024)[trial % 12]
            palette = [sum(1 << b for b in rng.sample(range(width), rng.randint(1, 5))) for _ in range(7)]
            terms = {tuple(rng.choice(palette) for _ in range(3)) for _ in range(3+trial)}
            terms.update(((1, 2, 12), (1, 4, 8)))  # A rank-two neutral change.
            terms = sorted(terms)
            raw = blob((32, 32, 32), terms)
            source.write_bytes(raw)
            for axis, reverse in product(range(3), (False, True)):
                expected, _ = refactor_shared(terms, axis, max_bits=1024, reverse_columns=reverse)
                for budget in (0, 1, 3000, 50000):
                    r = subprocess.run([basis, '--basis', str(source), str(target), str(budget),
                                        str(axis), str(int(reverse))], capture_output=True,
                                       text=True, timeout=30, check=True)
                    fields = r.stdout.split()
                    assert fields[0] == 'WIDE_BASIS' and len(fields) == 8
                    before, after, work, limited, axes, groups, saved = map(int,fields[1:])
                    shape, result = read_blob(target.read_bytes())
                    assert source.read_bytes() == raw and shape == (32,32,32)
                    assert before == len(terms) and after == len(result) <= before
                    assert limited in (0,1) and axes == 1-limited
                    assert budget == 0 or work <= budget
                    assert 0 <= groups <= saved <= before-after
                    same_tensor(terms, result)
                    if not limited:
                        assert result == sorted(expected), (trial, axis, reverse, budget)
                    counts['basis_runs'] += 1
                    counts['limited'] += limited
                    counts['neutral_changes'] += after == before and result != terms
            counts['basis_inputs'] += 1

        shapes = [(1,2,512), (2,1,512), (2,512,1), (31,2,3), (32,2,3),
                  (33,2,3), (2,31,3), (2,32,3), (2,33,3), (3,2,31),
                  (3,2,32), (3,2,33), (4,7,4), (5,5,5), (32,32,32)]
        for full in (False, True):
            for shape in shapes:
                if full and shape == (32,32,32):
                    continue  # Its naive tensor exceeds the existing term cap.
                terms = naive(shape) if full else sorted({tuple(
                    sum(1 << k for k in rng.sample(range(a*b), min(a*b, rng.randint(1,6))))
                    for a,b in ((shape[0],shape[1]), (shape[1],shape[2]), (shape[0],shape[2])))
                    for _ in range(13)})
                raw = blob(shape,terms)
                source.write_bytes(raw)
                for axis,size in enumerate(shape):
                    if size < 2:
                        continue
                    for removed in sorted({0,size//2,size-1}):
                        keep = [list(range(n)) for n in shape]
                        keep[axis].remove(removed)
                        expected = project_grid(shape,terms,keep)
                        r = subprocess.run([projection, '--project', str(source), str(target),
                                            str(axis), str(removed)], capture_output=True,
                                           text=True, timeout=30, check=True)
                        newshape,result = read_blob(target.read_bytes())
                        assert newshape == tuple(map(len,keep)) and result == expected
                        assert source.read_bytes() == raw
                        assert r.stdout.split() == ['WIDE_PROJECT', str(len(terms)),str(len(result))]
                        if full:
                            exact(newshape,result)
                            counts['projected_full_tensors'] += 1
                        counts['projections'] += 1

        source.write_bytes(blob((2,2,2),naive((2,2,2))))
        target.unlink()
        invalid = [(basis,'--basis',['1','3','0']), (basis,'--basis',['1','0','2']),
                   (projection,'--project',['3','0']), (projection,'--project',['0','2'])]
        for binary,mode,args in invalid:
            r = subprocess.run([binary,mode,str(source),str(target),*args],
                               capture_output=True,text=True,timeout=10)
            assert r.returncode != 0 and not target.exists()
        for budget,expected in ((0,1),(20000000,1),(1,-1)):
            r = subprocess.run([projection,'--verify',str(source),str(budget)],
                               capture_output=True,text=True,timeout=10)
            assert r.stdout.split() == ['WIDE_VERIFY',str(expected)]
            assert (r.returncode == 0) == (expected == 1)
        bad = naive((2,2,2)); u,v,w = bad[0]; bad[0] = (u,v,w^2)
        source.write_bytes(blob((2,2,2),bad))
        r = subprocess.run([projection,'--verify',str(source),'0'],
                           capture_output=True,text=True,timeout=10)
        assert r.returncode != 0 and r.stdout.split() == ['WIDE_VERIFY','0']
    assert counts['neutral_changes'] > 0 and counts['limited'] > 0
    result = dict(complete=True,record_claim=False,counts=counts,
                  binaries={Path(p).name:sha256(Path(p).read_bytes()).hexdigest() for p in (basis,projection)})
    if report:
        assert not report.exists()
        report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('basis', type=Path)
    p.add_argument('projection', type=Path)
    p.add_argument('--report', type=Path)
    a = p.parse_args()
    check(a.basis,a.projection,a.report)
