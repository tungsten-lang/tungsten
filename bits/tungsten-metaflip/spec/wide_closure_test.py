#!/usr/bin/env python3
"""Native closure parity, immutable replay, and rejection gates; no WR claim."""
from hashlib import sha256
from itertools import permutations
from pathlib import Path
import subprocess
import sys
import tempfile

from packed_composition_parity_test import naive, exact, orient
from wide_matrix_cleanup_parity_test import blob, read_blob

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'bits/tungsten-metaflip/tools'))
import screen_top_two_projection_children as top
from verify_composition_targets import block
from wide_composition_recipes import CompositionLibrary, read_leaf, PAIR_SOURCE


def replay_native_recipe(root, identity):
    """Independent replay of every frozen leaf, orientation and binary step."""
    base = Path(root) / 'composition/closure'
    pin = (base / 'plans' / identity).read_text().strip()
    raw = (base / 'recipes' / pin).read_bytes()
    assert sha256(raw).hexdigest() == pin
    rows = raw.decode().splitlines()
    tag, source, *nums = rows.pop(0).split()
    n, m, p, count = map(int, nums)
    assert tag == 'MFW_PLAN1' and source == identity and count == len(rows)
    if not rows:
        return None
    values = []
    for row in rows:
        f = row.split()
        kind, *dims = f[:5]
        shape = tuple(map(int, dims[:3])); rank = int(dims[3])
        if kind == 'N':
            assert len(f) == 5 and rank == shape[0]*shape[1]*shape[2]
            terms = naive(shape)
        elif kind == 'L':
            assert len(f) == 9
            body = (Path(root) / 'composition/objects' / f'{f[5]}.tensor').read_bytes()
            assert sha256(body).hexdigest() == f[5]
            parent, terms = read_blob(body)
            assert parent == tuple(map(int, f[6:])) and len(terms) == rank
            exact(parent, terms)
            terms = top.orient(parent, terms, shape)
        else:
            assert kind == 'B' and len(f) == 8
            axis, left, right = map(int, f[5:])
            assert 1 <= left <= len(values) and 1 <= right <= len(values)
            a, at = values[left-1]; b, bt = values[right-1]
            canonical = tuple(sorted(shape))
            if axis == 3:
                assert tuple(x*y for x, y in zip(a, b)) == canonical
                terms = top.kronecker(a, at, b, bt)
            else:
                assert axis in range(3)
                assert all(a[i]+b[i] == canonical[i] if i == axis else
                           a[i] == b[i] == canonical[i] for i in range(3))
                offset = [a[i] if i == axis else 0 for i in range(3)]
                terms = block(a, at, canonical, [0, 0, 0]) + block(b, bt, canonical, offset)
            terms = top.orient(canonical, terms, shape)
        assert len(terms) == rank
        values.append((shape, sorted(terms)))
    assert values[-1][0] == (n, m, p)
    exact(*values[-1])
    return values[-1]


def check(binary):
    runtime = ROOT / 'bits/tungsten-metaflip/lib/metaflip'
    with tempfile.TemporaryDirectory(prefix='metaflip-wide-closure-') as tmp:
        root = Path(tmp)
        def run(*args, ok=True):
            result = subprocess.run([binary, *map(str, args)], capture_output=True,
                                    text=True, timeout=60)
            assert (result.returncode == 0) == ok, (args, result.stdout, result.stderr)
            return result
        def store(name, shape, terms):
            exact(shape, terms)
            path = root / name
            path.write_bytes(blob(shape, sorted(terms)))
            return path
        seeds = runtime / 'seeds/gf2'
        shape, terms, _ = read_leaf(seeds / 'matmul_2x2_rank7_strassen_gf2.txt')
        strassen = store('strassen.mfw', shape, terms)
        cases = 0
        for a, b, kind in [((2, 3, 2), (3, 3, 2), 0),
                           ((3, 2, 4), (3, 3, 4), 1),
                           ((2, 4, 2), (2, 4, 3), 2),
                           ((2, 3, 2), (2, 2, 3), 3),
                           ((1, 2, 17), (2, 2, 1), 0),
                           ((1, 2, 17), (2, 2, 1), 3)]:
            if kind == 0 and a[2] != b[2]:
                b = (2, 2, 17)
            left = store('left.mfw', a, naive(a))
            right = store('right.mfw', b, naive(b))
            target = tuple(x*y if kind == 3 else x+y if i == kind else x
                           for i, (x, y) in enumerate(zip(a, b)))
            out = root / 'binary.mfw'
            run('--binary', left, right, kind, out)
            got_shape, got = read_blob(out.read_bytes())
            if kind == 3:
                expected = top.kronecker(a, naive(a), b, naive(b))
            else:
                offset = [a[i] if i == kind else 0 for i in range(3)]
                expected = block(a, naive(a), target, [0, 0, 0]) + block(b, naive(b), target, offset)
            assert got_shape == target and got == sorted(expected)
            exact(target, got)
            cases += 1
        out = root / 'strassen-product.mfw'
        run('--binary', strassen, strassen, 3, out)
        target, got = read_blob(out.read_bytes())
        assert target == (4, 4, 4) and got == sorted(top.kronecker(shape, terms, shape, terms))
        exact(target, got)
        run('--binary', strassen, strassen, 4, out, ok=False)
        limited = root / 'limited.mfw'
        run('--binary', strassen, strassen, 3, limited, 1, ok=False)
        assert not limited.exists()
        run('--binary', root / 'left.mfw', strassen, 1, out, ok=False)

        campaign = root / 'campaign'
        run('--catalog', campaign, runtime)
        marker = (campaign / 'composition/closure/catalog').read_bytes()
        run('--catalog', campaign, runtime)
        assert (campaign / 'composition/closure/catalog').read_bytes() == marker
        library = CompositionLibrary()
        for path in sorted(seeds.glob('matmul_*_gf2.txt')):
            s, t, _ = read_leaf(path)
            library._add(s, t, dict(state=path.name))
        s, t, _ = read_leaf(ROOT / PAIR_SOURCE)
        for coordinate in (4, 3):
            s, t = top.project(s, t, 2, coordinate)
        library._add(s, t, dict(state='pair'))
        # The real native task archive/publish path, not just a constructor.
        source = store('intake.mfw', (8, 8, 8), naive((8, 8, 8)))
        run('--register', campaign, source)
        source_id = sha256(source.read_bytes()).hexdigest()
        output = root / 'admitted.mfw'
        run('--task', campaign, source_id, output)
        s, admitted = read_blob(output.read_bytes())
        assert s == (8, 8, 8) and len(admitted) == library.recipe(s)['rank']
        exact(s, admitted)
        recipe_shape, recipe_terms = replay_native_recipe(campaign, source_id)
        assert recipe_shape == s and recipe_terms == admitted
        admitted_id = sha256(output.read_bytes()).hexdigest()
        assert (campaign / 'composition/best/8x8x8').read_text() == f'{len(admitted)} {admitted_id}\n'
        initial_tasks = (campaign / 'composition/transforms/submitted').read_bytes()
        run('--task', campaign, source_id, output)
        assert (campaign / 'composition/transforms/submitted').read_bytes() == initial_tasks
        assert sha256(output.read_bytes()).hexdigest() == admitted_id
        plans = []
        for target in [(4, 4, 4), (8, 8, 8), (5, 6, 7), (7, 12, 12),
                       *permutations((3, 4, 6)), (1, 7, 11)]:
            identity = sha256(repr(target).encode()).hexdigest()
            out = root / f'{identity}.mfw'
            run('--plan', campaign, identity, *target, 8001, out)
            s, got = read_blob(out.read_bytes())
            assert s == target and len(got) == library.recipe(target)['rank'], (target, len(got))
            exact(s, got)
            pin_path = campaign / 'composition/closure/plans' / identity
            pin = pin_path.read_text().strip()
            recipe = campaign / 'composition/closure/recipes' / pin
            assert sha256(recipe.read_bytes()).hexdigest() == pin
            assert replay_native_recipe(campaign, identity) == (s, got)
            plans.append((identity, target, out.read_bytes(), recipe))
            cases += 1
        # A future leaf must not silently replan an already frozen task.
        identity, target, before, recipe = plans[2]
        added = store('future.mfw', target, read_blob(before)[1])
        run('--register', campaign, added)
        out = root / 'replayed.mfw'
        run('--plan', campaign, identity, *target, 8001, out)
        assert out.read_bytes() == before
        # Corrupt recipe bytes, including a syntactically valid edit: digest gate.
        saved = recipe.read_bytes()
        recipe.write_bytes(saved.replace(b' B ', b' P ', 1) + b'\n')
        run('--plan', campaign, identity, *target, 8001, out, ok=False)
        recipe.write_bytes(saved)
        rows = saved.decode().splitlines()
        leaf = next(row.split() for row in rows[1:] if row.startswith('L '))
        path = campaign / 'composition/objects' / f'{leaf[5]}.tensor'
        leaf_body = path.read_bytes()
        path.write_bytes(leaf_body + b'\n')
        run('--replay', campaign, identity, recipe, out, ok=False)
        path.write_bytes(leaf_body)
        # Self-consistent hash of an incorrect tensor still fails the full gate.
        bad_shape, bad_terms = read_blob(leaf_body)
        bad_terms = bad_terms[1:]
        bad_body = blob(bad_shape, bad_terms)
        bad_id = sha256(bad_body).hexdigest()
        (path.parent / f'{bad_id}.tensor').write_bytes(bad_body)
        mutated = root / 'bad.recipe'
        mutated.write_text(saved.decode().replace(leaf[5], bad_id).replace(
            f'L {leaf[1]} {leaf[2]} {leaf[3]} {leaf[4]} ',
            f'L {leaf[1]} {leaf[2]} {leaf[3]} {len(bad_terms)} '))
        run('--replay', campaign, identity, mutated, out, ok=False)
        (campaign / 'stop').touch()
        run('--replay', campaign, identity, recipe, out, ok=False)
        print(f'PASS native wide closure: {cases} independent tensor/term/rank replays; frozen recipes and rejection gates')


if __name__ == '__main__':
    check(str(Path(sys.argv[1]).resolve()))
