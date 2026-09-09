#!/usr/bin/env python3
"""Deferred native contexts: shared capacity, independent journals, exact gates."""
from hashlib import sha256
from pathlib import Path
import os
import subprocess
import sys
import tempfile

from composition_queue_test import (RUNTIME, audit, completion, exact, naive, narrow,
                                    parse_terms, read_record, replace_record, store, value)
from mixed_composition_parity_test import load_bank, optimal, components
from mixed_group_composition_parity_test import context_prices, group_components, optimal as group_optimal
from packed_composition_parity_test import orient


def setup(root):
    for name in ('objects', 'tasks', 'results', 'by-id'):
        (root/name).mkdir(parents=True, exist_ok=True)


def pending(root):
    q = root/'composition'; m = q/'mixed'
    return value(q/'submitted')-value(q/'consumed')+value(m/'submitted')-value(m/'consumed')


def deferred(root):
    m = root/'composition/mixed'
    return 27*value(m/'parent-submitted')-value(m/'context')


def mixed_audit(root):
    q = root/'composition'; m = q/'mixed'
    seen = set(); outputs = set(); banks = {}
    for ordinal in range(1, value(m/'consumed')+1):
        ticket, result = completion(m, ordinal)
        assert ticket not in seen and 1 <= ticket <= value(m/'submitted')
        seen.add(ticket)
        raw = read_record(m, 'tasks', ticket)
        fields = raw.decode().split()
        assert len(fields) == 9 and fields[0] in ('MFM1', 'MFM2')
        parent_ticket, context, n, k, p, price = map(int, fields[3:])
        assert 0 <= context < 27
        parent_version = 'MFMD2' if fields[0] == 'MFM2' else 'MFMD1'
        assert read_record(m, 'parents', parent_ticket) == f'{parent_version} {fields[1]} {fields[2]}\n'.encode()
        shape, terms = narrow(root, fields[1])
        scales = (2+context//9, 2+(context//3)%3, 2+context%3)
        target = tuple(x*y for x,y in zip(shape, scales))
        assert target == (n,k,p)
        if fields[2] not in banks:
            banks[fields[2]] = load_bank(root, fields[2])
        leaves = banks[fields[2]]
        a,b,c = scales
        costs = [len(leaves[tuple(sorted(s))]) for s in (scales,(a,b,2*c),(2*a,b,c),(a,2*b,c))]
        if fields[0] == 'MFM2':
            costs = context_prices(scales, leaves)
            if all(len(g) <= 12 for g in group_components(terms, costs)):
                # Recipes bind a probe budget, not a claim of optimality.
                # Exact-equality checks live in the engine test, which sees
                # the explicit completion/fallback status for every plan.
                assert group_optimal(terms, costs) <= price
        elif all(len(g) <= 16 for g in components(terms, costs)):
            assert price == optimal(terms, costs)
        assert result[1] == sha256(raw).hexdigest()
        data = (q/'objects'/f'{result[2]}.tensor').read_bytes()
        assert sha256(data).hexdigest() == result[2]
        lines = data.decode().splitlines(); header = lines.pop(0).split()
        got = [tuple(int(v,16) for v in row.split()) for row in lines]
        assert header == ['MFW1', *map(str,target), str(len(got))]
        assert 0 < len(got) <= price
        exact(target, got)
        assert result[3:] == ['x'.join(map(str,target)), str(len(got))]
        outputs.add((target, len(got)))
    return outputs


def check(binary):
    base_env = dict(os.environ, METAFLIP_COMPOSITION_PENDING='1269', METAFLIP_COMPOSITION_FIFO='0')
    base_env.pop('METAFLIP_COMPOSITION_MIXED', None)  # Test default-on, not an opt-in.
    base_env.pop('METAFLIP_COMPOSITION_MIXED_GROUPS', None)

    def run(*args, ok=True, off=False, unlimited=False, pairs=False):
        env = dict(base_env)
        if off:
            env['METAFLIP_COMPOSITION_MIXED'] = '0'
        if unlimited:
            env['METAFLIP_COMPOSITION_PENDING'] = '0'
        if pairs:
            env['METAFLIP_COMPOSITION_MIXED_GROUPS'] = '0'
        p = subprocess.run([binary, *map(str,args)], env=env, capture_output=True, text=True, timeout=60)
        assert (p.returncode == 0) == ok, (args, p.returncode, p.stdout, p.stderr)
        return p.stdout

    with tempfile.TemporaryDirectory(prefix='metaflip-mixed-queue-') as directory:
        root = Path(directory); setup(root)
        terms = naive((2,2,2)); key = store(root, (2,2,2), terms)
        run('--prepare', root, RUNTIME, key)
        q = root/'composition'; m = q/'mixed'
        assert value(q/'submitted') == 9 and value(m/'submitted') == 0 and deferred(root) == 27
        parent_record = read_record(m, 'parents', 1)
        assert parent_record.startswith(b'MFMD2 ')
        stamp = m/'by-parent'/sha256(parent_record).hexdigest()
        # Parent record before cursor/index commit: repair, not a duplicate.
        (m/'parent-submitted').write_text('0\n'); stamp.unlink()
        run('--prepare', root, RUNTIME, key)
        assert value(m/'parent-submitted') == 1 and stamp.read_text() == '1\n'
        old_records = [read_record(q,'tasks',i) for i in range(1,10)]
        (root/'stop').write_text('stop\n')
        run('--compose-batch', root, 4)
        assert pending(root) == 9 and deferred(root) == 27 and value(q/'consumed') == 0
        (root/'stop').unlink()
        run('--compose-batch', root, 1)
        assert value(q/'consumed') == 1 and value(m/'consumed') == 0
        assert value(m/'submitted') == 27 and deferred(root) == 0
        mixed_records = [read_record(m,'tasks',i) for i in range(1,28)]
        # Lost mixed recipe counter/cursor, then lost only the cursor.
        for lose_counter in (True, False):
            (m/'context').write_text('26\n')
            if lose_counter:
                (m/'submitted').write_text('26\n')
            run('--prepare', root, RUNTIME, key)
            assert value(m/'submitted') == value(m/'context') == 27
            assert [read_record(m,'tasks',i) for i in range(1,28)] == mixed_records
            assert [read_record(q,'tasks',i) for i in range(1,10)] == old_records
        original = read_record(m,'tasks',1); fields = original.decode().split()
        bad = fields.copy(); bad[-1] = str(int(bad[-1])+1)
        replace_record(m,'tasks',1,(' '.join(bad)+'\n').encode())
        before = set((q/'objects').iterdir())
        run('--compose-batch', root, 1, ok=False)
        assert value(m/'consumed') == 0 and set((q/'objects').iterdir()) == before
        replace_record(m,'tasks',1,original)
        bank = q/'banks'/fields[2]; saved = bank.read_bytes()
        bank.write_bytes(saved+b' ')
        run('--compose-batch', root, 1, ok=False)
        assert value(m/'consumed') == 0 and set((q/'objects').iterdir()) == before
        bank.write_bytes(saved)
        dependency = saved.decode().split()[-1]
        leaf = root/'objects'/f'{dependency}.tensor'; leaf_raw = leaf.read_bytes(); leaf.unlink()
        run('--compose-batch', root, 1, ok=False)
        assert value(m/'consumed') == 0 and set((q/'objects').iterdir()) == before
        leaf.write_bytes(leaf_raw)
        run('--compose-batch', root, 1)
        assert value(m/'consumed') == 1 and not (m/'error').exists()
        first_result = read_record(m,'results',1)
        (m/'consumed').write_text('0\n')
        while value(m/'consumed') < 1:
            run('--compose-batch', root, 1)
        assert read_record(m,'results',1) == first_result
        # Same-rank, different complete tensors must both receive contexts.
        for name in ('matmul_2x2_rank7_strassen_gf2.txt', 'matmul_2x2_rank7_d36_gl120_gf2.txt'):
            variant = store(root,(2,2,2),parse_terms((RUNTIME/'seeds/gf2'/name).read_bytes(),7))
            run('--prepare',root,RUNTIME,variant)
            run('--prepare',root,RUNTIME,variant)
        assert value(m/'parent-submitted') == 3 and deferred(root) == 54
        # Disabling new intake does not abandon already committed contexts.
        off_key = store(root,(2,2,2),terms+[terms[0]]*2)
        run('--prepare',root,RUNTIME,off_key,off=True)
        assert value(m/'parent-submitted') == 3
        while pending(root) or deferred(root):
            run('--compose-batch',root,4,off=True)
        assert value(m/'submitted') == value(m/'consumed') == 81
        audit(root); mixed_audit(root)
        assert value(m/'failures') == 3
        assert [read_record(q,'tasks',i) for i in range(1,10)] == old_records
        saved_tasks = [read_record(m,'tasks',i) for i in range(1,82)]
        saved_banks = {p:p.read_bytes() for p in (q/'banks').iterdir()}
        # New exact leaf representation reprices a re-offered parent without
        # editing earlier dependencies, tasks, results or full tensor objects.
        leaf_id = (q/'leaves/4').read_text().strip()
        shape, tensor = narrow(root,leaf_id)
        variant = store(root,shape,orient(shape,tensor,(0,2,1)))
        assert variant != leaf_id
        (q/'leaves/4').write_text(variant+'\n')
        run('--prepare',root,RUNTIME,key)
        assert value(m/'parent-submitted') == 4 and deferred(root) == 27
        run('--prepare',root,RUNTIME,key)
        assert value(m/'parent-submitted') == 4
        while pending(root) or deferred(root):
            run('--compose-batch',root,4)
        assert value(m/'consumed') == 108
        assert [read_record(m,'tasks',i) for i in range(1,82)] == saved_tasks
        assert all(p.read_bytes() == raw for p,raw in saved_banks.items())
        mixed_audit(root)
        print('PASS mixed queue: default intake, ties, 3 exact-gate failures, independent journals and restart',flush=True)

    with tempfile.TemporaryDirectory(prefix='metaflip-mixed-versions-') as directory:
        root = Path(directory); setup(root)
        key = store(root, (2,2,3), naive((2,2,3)))
        run('--prepare', root, RUNTIME, key, pairs=True)
        q = root/'composition'; m = q/'mixed'
        old_parent = read_record(m, 'parents', 1)
        assert old_parent.startswith(b'MFMD1 ')
        run('--mixed-admit', root, 1)
        old_task = read_record(m, 'tasks', 1)
        assert old_task.startswith(b'MFM1 ')
        run('--prepare', root, RUNTIME, key)
        assert value(m/'parent-submitted') == 2
        assert read_record(m, 'parents', 2).startswith(b'MFMD2 ')
        run('--prepare', root, RUNTIME, key, pairs=True)
        run('--prepare', root, RUNTIME, key)
        assert value(m/'parent-submitted') == 2
        # New offers do not change an old ticket's planner or leaf identity.
        while pending(root) or deferred(root):
            run('--compose-batch', root, 4, pairs=True)
        assert value(m/'consumed') == 54
        assert read_record(m, 'parents', 1) == old_parent and read_record(m, 'tasks', 1) == old_task
        plans = [read_record(m, 'tasks', i).decode().split() for i in range(1,55)]
        assert all(p[0] == 'MFM1' for p in plans[:27])
        assert all(p[0] == 'MFM2' for p in plans[27:])
        assert all(int(new[-1]) <= int(old[-1]) for old,new in zip(plans[:27], plans[27:]))
        assert any(int(new[-1]) < int(old[-1]) for old,new in zip(plans[:27], plans[27:]))
        mixed_audit(root)
        # A recipe cannot select a different algorithm than its parent ticket.
        bad = plans[-1].copy(); bad[0] = 'MFM1'
        raw = read_record(m, 'tasks', 54)
        replace_record(m, 'tasks', 54, (' '.join(bad)+'\n').encode())
        run('--mixed-admit', root, 1, ok=False)
        replace_record(m, 'tasks', 54, raw)
        run('--mixed-admit', root, 1)
        print('PASS mixed versions: old/new coexist, group gains, exact replay and algorithm binding',flush=True)

    with tempfile.TemporaryDirectory(prefix='metaflip-mixed-cap-') as directory:
        root = Path(directory); setup(root)
        terms = naive((2,2,2))
        for copies in range(50):
            key = store(root,(2,2,2),terms+[terms[0]]*(2*copies))
            run('--prepare',root,RUNTIME,key)
        q = root/'composition'; m = q/'mixed'
        assert value(q/'submitted') == 450 and deferred(root) == 1350
        for _ in range(50):
            run('--mixed-admit',root,27)
            assert pending(root) <= 1269
        assert pending(root) == 1269 and deferred(root) == 531
        before = (value(m/'context'), value(m/'submitted'))
        run('--mixed-admit',root,27)
        assert (value(m/'context'), value(m/'submitted')) == before
        # A new source reserves room against BOTH lanes before writing any
        # derived output. Mixed admission yields freed slots to that source.
        source = store(root,(2,2,2),terms)
        (root/'tasks/1').write_text(source+'\n')
        objects = set((root/'objects').iterdir())
        text = run('--refine-batch',root,1,1,RUNTIME)
        assert 'reason=composition-backpressure' in text and not (root/'results/1').exists()
        assert set((root/'objects').iterdir()) == objects
        reserve = int((root/'backpressure').read_text().split()[2])
        for _ in range((reserve+3)//4):
            run('--compose-batch',root,4)
            assert value(m/'context') == before[0] and pending(root) <= 1269
        run('--refine-batch',root,1,1,RUNTIME)
        assert (root/'results/1').exists() and not (root/'backpressure').exists()
        assert pending(root) <= 1269
        audit(root); mixed_audit(root)
        # An over-limit existing queue drains; it is never dropped or reset.
        while pending(root) < 1269 and deferred(root):
            run('--mixed-admit',root,27)
        run('--mixed-admit',root,27,unlimited=True)
        assert pending(root) > 1269
        after = value(m/'context')
        run('--mixed-admit',root,27)
        assert value(m/'context') == after
        run('--compose-batch',root,4)
        assert value(m/'context') == after
        print('PASS mixed capacity: exact shared 1269 cap, source reservation, drain priority, unlimited control',flush=True)

    with tempfile.TemporaryDirectory(prefix='metaflip-mixed-coordinator-') as directory:
        root = Path(directory); setup(root)
        terms = parse_terms((RUNTIME/'seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt').read_bytes(),7)
        key = store(root,(2,2,2),terms)
        run('--prepare',root,RUNTIME,key)
        assert value(root/'composition/submitted') == 0 and deferred(root) == 27
        text = run('--mixed-coordinator',root,RUNTIME)
        assert 'PASS mixed coordinator' in text and ' compose_deferred=0 ' in text
        assert ' compose_submitted=27 ' in text and ' compose_completed=27 ' in text
        assert 'deferred 0;' in text
        mixed_audit(root)
        ps = subprocess.check_output(['ps','-axo','pid=,command='],text=True)
        assert not any(str(root) in line and ('--refine-batch' in line or '--compose-batch' in line) for line in ps.splitlines())
        print('PASS deferred-only coordinator: automatic admission, 27 exact outputs, status/TUI and stop',flush=True)


if __name__ == '__main__':
    check(sys.argv[1])
