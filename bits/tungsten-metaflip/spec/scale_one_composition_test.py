#!/usr/bin/env python3
"""Scale-one witnesses, substitution, immutable domains and cold-queue replay."""
from itertools import product
from pathlib import Path
from hashlib import sha256
import argparse
import os
import subprocess
import tempfile

from composition_queue_test import RUNTIME, audit, read_record, replace_record, store, value
from mixed_composition_parity_test import (composition_case as pair_case, load_bank,
                                           unit_leaves)
from mixed_group_composition_parity_test import composition_case as group_case
from mixed_grid_composition_parity_test import (composition_case as grid_case,
                                                context_prices, dense_naive, run as grid_run)
from mixed_composition_queue_test import deferred, mixed_audit, pending, setup
from packed_composition_parity_test import exact, naive, parse_terms


def check(groups, pairs, queue, root, parent=None):
    env = dict(os.environ, METAFLIP_COMPOSITION_PENDING='1269', METAFLIP_COMPOSITION_FIFO='1')
    for key in ('METAFLIP_COMPOSITION_MIXED', 'METAFLIP_COMPOSITION_MIXED_GROUPS',
                'METAFLIP_COMPOSITION_GRIDS', 'METAFLIP_COMPOSITION_SCALE_ONE'):
        env.pop(key, None)

    def run(*args, settings=None, ok=True):
        result = subprocess.run([str(queue), *map(str, args)], capture_output=True, text=True,
                                timeout=60, env=env | (settings or {}))
        assert (result.returncode == 0) == ok, (args, result.stdout, result.stderr)
        return result.stdout

    def drain(path, settings=None):
        for _ in range(100):
            if not pending(path) and not deferred(path):
                return
            run('--compose-batch', path, 4, settings=settings)
        raise AssertionError('bounded queue did not drain')

    direct = root/'direct'; setup(direct)
    bank_id = subprocess.check_output([str(pairs), '--bank', str(direct), str(RUNTIME)],
                                      text=True, timeout=60).strip().splitlines()[-1]
    bank_raw = (direct/'composition/banks'/bank_id).read_bytes()
    leaves = unit_leaves(load_bank(direct, bank_id))
    grid_run(groups, '--unit-leaves-test')
    # The unsupported optional 1x4x16 and 1x8x8 leaves must not become
    # negative masks. Their absence must not disable a whole valid context.
    assert (1,4,16) not in leaves and (1,8,8) not in leaves
    assert context_prices((1,4,4), leaves)[-2] == -1
    cases = 0
    for scales in product(range(1,5), repeat=3):
        if 1 not in scales or scales == (1,1,1):
            continue
        shape = (2,2,2); terms = naive(shape)
        pair_case(str(pairs), direct, bank_id, leaves, shape, terms, scales)
        group_case(str(groups), direct, bank_id, leaves, shape, terms, scales)
        grid_case(groups, direct, bank_id, leaves, shape, terms, scales)
        cases += 3
    for scales in ((3,1,3), (1,4,4), (4,1,2)):
        grid_case(groups, direct, bank_id, leaves, (2,2,2), naive((2,2,2)), scales, budget=1)
        cases += 1
    for scales in ((1,4,4), (4,1,4), (4,4,1)):
        grid_case(groups, direct, bank_id, leaves, (1,63,1), naive((1,63,1)), scales)
        cases += 1
    for kind,shape in ((3,(2,1,2)),(4,(1,2,2)),(5,(2,2,1))):
        grid_case(groups,direct,bank_id,leaves,shape,dense_naive(shape),(1,2,3),forced=kind)
        cases += 1
    if parent is not None:
        terms = parse_terms(parent.read_bytes(), 85); exact((4,7,4), terms)
        for scales, bound in (((3,1,3),651), ((4,1,4),1132)):
            price, rank, _, _ = grid_case(groups, direct, bank_id, leaves, (4,7,4), terms, scales)
            assert price == rank == bound, (scales,price,rank)
            cases += 1
    assert (direct/'composition/banks'/bank_id).read_bytes() == bank_raw
    print(f'PASS scale-one composition: {cases} independent substitution/full-tensor replays; immutable 22-leaf bank', flush=True)

    # Upgrade each planner separately: old tickets and task bytes survive,
    # while re-offering the same parent adds only its new 27-context domain.
    path = root/'versions'; setup(path)
    key = store(path, (2,2,2), naive((2,2,2)))
    settings = ({'METAFLIP_COMPOSITION_MIXED_GROUPS':'0'},
                {'METAFLIP_COMPOSITION_GRIDS':'0'}, {})
    for setting in settings:
        run('--prepare',path,RUNTIME,key,settings=setting | {'METAFLIP_COMPOSITION_SCALE_ONE':'0'})
        run('--mixed-admit',path,27)
    mixed = path/'composition/mixed'
    old = [read_record(mixed,'tasks',i) for i in range(1,82)]
    for setting in settings:
        run('--prepare',path,RUNTIME,key,settings=setting)
        run('--prepare',path,RUNTIME,key,settings=setting)
    assert value(mixed/'parent-submitted') == 6 and deferred(path) == 81
    assert [read_record(mixed,'tasks',i) for i in range(1,82)] == old
    drain(path, {'METAFLIP_COMPOSITION_SCALE_ONE':'0'})
    assert value(mixed/'consumed') == 162
    records = [read_record(mixed,'tasks',i).decode().split() for i in range(1,163)]
    for version in range(1,7):
        assert all(row[0] == f'MFM{version}' for row in records[(version-1)*27:version*27])
    for left,right in ((3,4),(4,5)):
        assert all(int(b[-1]) <= int(a[-1]) for a,b in zip(records[left*27:(left+1)*27],records[right*27:(right+1)*27]))
    audit(path); mixed_audit(path)
    print('PASS scale-one versions: all six planners/domains coexist, 162 exact outputs and unchanged legacy recipes',flush=True)

    path = root/'recovery'; setup(path)
    key = store(path,(2,2,2),naive((2,2,2)))
    run('--prepare',path,RUNTIME,key)  # Default-on, two immutable offers.
    mixed = path/'composition/mixed'
    assert value(mixed/'parent-submitted') == 2 and deferred(path) == 54
    tail = read_record(mixed,'parents',2)
    assert tail.startswith(b'MFMD6 ')
    (mixed/'parent-submitted').write_text('1\n')
    (mixed/'by-parent'/sha256(tail).hexdigest()).unlink()
    run('--prepare',path,RUNTIME,key)
    assert value(mixed/'parent-submitted') == 2
    (path/'stop').write_text('stop\n'); run('--mixed-admit',path,27)
    assert deferred(path) == 54
    (path/'stop').unlink()
    run('--mixed-admit',path,27)
    assert value(mixed/'submitted') == 27 and deferred(path) == 27
    run('--mixed-admit',path,27)
    assert value(mixed/'submitted') == 54 and deferred(path) == 0
    saved = [read_record(mixed,'tasks',i) for i in range(1,55)]
    for lose_counter in (True,False):
        (mixed/'context').write_text('53\n')
        if lose_counter:
            (mixed/'submitted').write_text('53\n')
        run('--prepare',path,RUNTIME,key)
        assert value(mixed/'submitted') == value(mixed/'context') == 54
        assert [read_record(mixed,'tasks',i) for i in range(1,55)] == saved
    for column,bad in ((0,'MFM3'),(0,'MFM7'),(0,'MFM06'),(4,'27'),(4,'-1'),(4,'026')):
        fields = saved[-1].decode().split(); fields[column] = bad
        replace_record(mixed,'tasks',54,(' '.join(fields)+'\n').encode())
        run('--mixed-admit',path,1,ok=False)
    replace_record(mixed,'tasks',54,saved[-1])
    drain(path, {'METAFLIP_COMPOSITION_MIXED':'0','METAFLIP_COMPOSITION_SCALE_ONE':'0'})
    audit(path); mixed_audit(path)
    assert value(mixed/'consumed') == 54
    print('PASS scale-one recovery: two-offer tail, lost task/cursor, six domain mutations, stop and disabled-intake drain',flush=True)

    path = root/'capacity'; setup(path)
    terms = naive((2,2,2))
    for copies in range(25):
        key = store(path,(2,2,2),terms+[terms[0]]*(2*copies))
        run('--prepare',path,RUNTIME,key)
    mixed = path/'composition/mixed'
    assert value(mixed/'parent-submitted') == 50 and deferred(path) == 1350
    for _ in range(50):
        run('--mixed-admit',path,27)
        assert pending(path) <= 1269
    assert pending(path) == 1269 and deferred(path) == 306
    before = value(mixed/'context')
    run('--mixed-admit',path,27)
    assert value(mixed/'context') == before
    print('PASS scale-one capacity: dual-domain intake still obeys shared 1269 cap and 27-context slices',flush=True)

    path = root/'coordinator'; setup(path)
    terms = parse_terms((RUNTIME/'seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt').read_bytes(),7)
    key = store(path,(2,2,2),terms); run('--prepare',path,RUNTIME,key)
    assert deferred(path) == 54 and pending(path) == 0
    text = run('--mixed-coordinator',path,RUNTIME)
    assert ' compose_submitted=54 ' in text and ' compose_completed=54 ' in text and ' compose_deferred=0 ' in text
    assert 'deferred 0;' in text
    mixed_audit(path)
    ps = subprocess.check_output(['ps','-axo','pid=,command='],text=True)
    assert not any(str(path) in line and ('--refine-batch' in line or '--compose-batch' in line) for line in ps.splitlines())
    print('PASS scale-one coordinator: 54 automatic exact outputs, status/TUI and no surviving worker',flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('groups',type=Path)
    parser.add_argument('pairs',type=Path)
    parser.add_argument('queue',type=Path)
    parser.add_argument('--parent',type=Path)
    parser.add_argument('--root',type=Path)
    args = parser.parse_args()
    if args.root:
        args.root.mkdir(parents=True,exist_ok=False)
        check(args.groups,args.pairs,args.queue,args.root,args.parent)
    else:
        with tempfile.TemporaryDirectory(prefix='metaflip-scale-one-') as directory:
            check(args.groups,args.pairs,args.queue,Path(directory),args.parent)
