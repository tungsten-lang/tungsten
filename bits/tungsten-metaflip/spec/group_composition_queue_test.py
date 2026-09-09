#!/usr/bin/env python3
"""Matched pair/group intake, exact dependency gates and immutable recovery."""
from hashlib import sha256
from pathlib import Path
import os
import subprocess
import sys
import tempfile
from composition_queue_test import RUNTIME, audit, narrow, read_record, replace_record, store, value
from packed_composition_parity_test import orient, parse_terms


def check(binary):
    def run(*args, groups=True, ok=True):
        result = subprocess.run([binary,*map(str,args)], capture_output=True,text=True,timeout=60,
                                env=dict(os.environ,METAFLIP_COMPOSITION_GROUPS='1' if groups else '0',
                                         METAFLIP_COMPOSITION_FIFO='1'))
        assert (result.returncode == 0) == ok, (args,result.stdout,result.stderr)
        return result

    with tempfile.TemporaryDirectory(prefix='metaflip-group-queue-') as d:
        root = Path(d); (root/'objects').mkdir()
        terms = parse_terms((RUNTIME/'seeds/gf2/matmul_2x2x8_rank28_catalog_gf2.txt').read_bytes(),28)
        key = store(root,(2,2,8),terms)
        run('--prepare',root,RUNTIME,key,groups=False)
        q = root/'composition'; old_count = value(q/'submitted')
        old_stamp = (q/'parents'/key).read_bytes()
        assert 0 < old_count <= 9 and not (q/'banks').exists()
        old = [read_record(q,'tasks',i) for i in range(1,old_count+1)]
        assert all(record.startswith(b'MFC1 ') for record in old)
        while value(q/'consumed') < old_count: run('--compose-batch',root,4)
        assert ((8,8,8),364) in audit(root)
        # Upgrade the same parent; previous pair recipes remain immutable.
        run('--prepare',root,RUNTIME,key)
        new_count = value(q/'submitted')
        assert old_count < new_count <= old_count+9
        assert [read_record(q,'tasks',i) for i in range(1,old_count+1)] == old
        added = [read_record(q,'tasks',i) for i in range(old_count+1,new_count+1)]
        assert all(record.startswith(b'MCG1 ') for record in added)
        run('--prepare',root,RUNTIME,key)
        assert value(q/'submitted') == new_count
        # Simulate the last parent's tasks committed before its marker/cursor.
        (q/'parents'/key).write_bytes(old_stamp); (q/'submitted').write_text(str(old_count)+'\n')
        run('--prepare',root,RUNTIME,key)
        assert value(q/'submitted') == new_count
        ticket = old_count+1; original = read_record(q,'tasks',ticket)
        fields = original.decode().split()

        def reject_task(mutated):
            replace_record(q,'tasks',ticket,(' '.join(mutated)+'\n').encode())
            before = set((q/'objects').iterdir())
            run('--compose-batch',root,1,ok=False)
            assert value(q/'consumed') == old_count and set((q/'objects').iterdir()) == before
            replace_record(q,'tasks',ticket,original)

        changed = fields.copy(); changed[-1] = str(int(fields[-1])+1)
        reject_task(changed)
        manifest_path = q/'banks'/fields[2]; manifest = manifest_path.read_bytes()
        manifest_path.write_bytes(manifest+b' ')
        reject_task(fields)
        manifest_path.write_bytes(manifest)
        member_ids = manifest.decode().split()
        missing = member_ids[-1]; member_path = root/'objects'/f'{missing}.tensor'
        member_bytes = member_path.read_bytes(); member_path.unlink()
        reject_task(fields)
        member_path.write_bytes(member_bytes)
        # Both replacement manifests have valid hashes. One has a wrong-shape
        # member; the other has the correct shape but a false tensor identity.
        for false_tensor in (False,True):
            bad = member_ids.copy()
            if false_tensor:
                shape, leaf = narrow(root,bad[4])
                leaf = leaf.copy(); u,v,w = leaf[0]; leaf[0] = (u ^ 2 if u != 2 else u ^ 1,v,w)
                bad[4] = store(root,shape,leaf)
            else:
                bad[4] = bad[3]
            raw = (' '.join(bad)+'\n').encode(); bad_id = sha256(raw).hexdigest()
            (q/'banks'/bad_id).write_bytes(raw)
            changed = fields.copy(); changed[2] = bad_id
            reject_task(changed)
        assert value(q/'failures') == 5
        while value(q/'consumed') < new_count: run('--compose-batch',root,4)
        assert ((8,8,8),329) in audit(root)
        assert not (q/'error').exists()
        # A changed valid same-rank pair leaf rebuilds the bank, but only
        # reprices axes at that scale. Previous bank bytes are preserved.
        old_banks = {p:p.read_bytes() for p in (q/'banks').iterdir()}
        leaf_key = (q/'leaves/4').read_text().strip()
        shape, leaf = narrow(root,leaf_key)
        variant = store(root,shape,orient(shape,leaf,(0,2,1)))
        assert variant != leaf_key
        (q/'leaves/4').write_text(variant+'\n')
        run('--prepare',root,RUNTIME,key)
        final_count = value(q/'submitted')
        assert new_count < final_count <= new_count+3
        assert all(read_record(q,'tasks',i).decode().split()[4] == '4'
                   for i in range(new_count+1,final_count+1))
        assert all(p.read_bytes() == raw for p,raw in old_banks.items())
        run('--prepare',root,RUNTIME,key)
        assert value(q/'submitted') == final_count
        while value(q/'consumed') < final_count: run('--compose-batch',root,4)
        audit(root)
        print(f'PASS grouped queue: {old_count} pair recipes + {new_count-old_count} group upgrades; '
              '5 forged/missing dependency rejections; known 8x8x8 364 -> 329')


if __name__ == '__main__':
    check(sys.argv[1])
