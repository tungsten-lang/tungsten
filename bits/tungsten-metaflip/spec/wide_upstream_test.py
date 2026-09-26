#!/usr/bin/env python3
"""Library-versioned native upstream replay; fixtures are not record claims."""
from hashlib import sha256
from pathlib import Path
import subprocess
import shutil
import os
import sys
import tempfile

from composition_queue_test import read_record
from packed_composition_parity_test import naive, exact
from wide_matrix_cleanup_parity_test import blob, read_blob
from wide_closure_test import ROOT, read_leaf


def check(binary, public=None):
    with tempfile.TemporaryDirectory(prefix='metaflip-upstream-') as temp:
        root = Path(temp)
        def run(*args, ok=True, **environment):
            p = subprocess.run([binary, *map(str,args)], capture_output=True,
                               text=True, timeout=30,
                               env=dict(os.environ,**environment))
            assert (p.returncode == 0) == ok, (args,p.stdout,p.stderr)
            return p.stdout.strip()
        def store(shape, terms, name):
            path = root/name
            path.write_bytes(blob(shape, sorted(terms)))
            exact(shape, terms)
            return path
        campaign = root/'campaign'
        (campaign/'composition/best').mkdir(parents=True)
        parent = store((4,4,4), naive((4,4,4)), 'parent.mfw')
        larger = store((6,6,6), naive((6,6,6)), 'larger.mfw')
        leaf = store((2,2,2), naive((2,2,2)), 'leaf.mfw')
        for path in (parent, larger, leaf):
            run('--register',campaign,path)
        source = sha256(parent.read_bytes()).hexdigest()
        frozen = root/'original-plan.mfw'
        # No cheaper body yet: the original source ticket freezes a zero plan.
        run('--plan',campaign,source,4,4,4,64,frozen,ok=False)
        base = campaign/'composition/closure'
        old_pin = (base/'plans'/source).read_bytes()
        old_recipe = (base/'recipes'/old_pin.decode().strip()).read_bytes()
        assert old_recipe.endswith(b'4 4 4 0\n')
        assert run('--pending',campaign) == '1'
        assert run('--pending',campaign,METAFLIP_WIDE_TRANSFORMS='0') == '0'
        run('--sweep',campaign,METAFLIP_WIDE_TRANSFORMS='0')
        assert not (base/'sweep').exists()
        run('--sweep',campaign)
        assert run('--pending',campaign) == '0'
        assert not (campaign/'composition/transforms/submitted').exists()

        shape, terms, _ = read_leaf(ROOT/'bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt')
        better = store(shape, terms, 'strassen.mfw')
        run('--register',campaign,better)
        assert run('--pending',campaign) == '1'
        q = campaign/'composition/transforms'
        q.mkdir(parents=True)
        (q/'submitted').write_text('256\n')
        checkpoint = (base/'sweep').read_bytes()
        run('--sweep',campaign)
        assert (base/'sweep').read_bytes() == checkpoint
        (q/'submitted').write_text('0\n')
        (base/'sweep').write_text(f'MFW_SWEEP1 {sha256((base/"leaves").read_bytes()).hexdigest()} 0\n')
        assert run('--pending',campaign) == '1'
        run('--sweep',campaign,ok=False)
        (base/'sweep').write_bytes(checkpoint)
        run('--sweep',campaign)
        assert (q/'submitted').read_text() == '1\n'
        tag, context, mode = read_record(q,'tasks',1).decode().split()
        assert tag == 'MFT_TASK1' and mode == '3137'
        ctx = (base/'contexts'/context).read_bytes()
        assert sha256(ctx).hexdigest() == context
        _, parent_id, library_pin = ctx.decode().split()
        assert parent_id == source
        snapshot = (base/'libraries'/library_pin).read_bytes()
        assert sha256(snapshot).hexdigest() == library_pin
        new_pin = (base/'plans'/context).read_bytes()
        plan = (base/'recipes'/new_pin.decode().strip()).read_bytes()
        assert (base/'plans'/source).read_bytes() == old_pin
        assert (base/'recipes'/old_pin.decode().strip()).read_bytes() == old_recipe

        # Recover an offered row whose cursor commit was interrupted.
        header, pin, cursor = (base/'sweep').read_text().split()
        (base/'sweep').write_text(f'{header} {pin} {int(cursor)-1}\n')
        run('--sweep',campaign)
        assert (q/'submitted').read_text() == '1\n'
        # Changing library heads cannot alter a queued pinned recipe.
        run('--register',campaign,larger)
        assert (base/'plans'/context).read_bytes() == new_pin
        if public is not None:
            live=root/'public-batch'
            shutil.copytree(campaign,live)
            p=subprocess.run([public,'--compose-batch',str(live),'1',''],
                             capture_output=True,text=True,timeout=30)
            assert p.returncode==0,(p.stdout,p.stderr)
            assert (live/'composition/transforms/consumed').read_text()=='1\n'
            live_result=read_record(live/'composition/transforms','results',1).decode().split()
            assert int(live_result[7])==49
            exact(*read_blob((live/'composition/objects'/f'{live_result[2]}.tensor').read_bytes()))
            assert int((live/'composition/feedback/submitted').read_text())>=1
            from wide_transform_queue_test import audit
            assert audit(live)['closure_reprice']==1
        run('--task-at',campaign,1)
        result = read_record(q,'results',1).decode().split()
        assert result[1] == sha256(read_record(q,'tasks',1)).hexdigest()
        assert tuple(map(int,result[3:6])) == (4,4,4)
        assert int(result[6]) == 64 and int(result[7]) == 49
        body = (campaign/'composition/objects'/f'{result[2]}.tensor').read_bytes()
        out_shape, out_terms = read_blob(body)
        exact(out_shape,out_terms)
        assert len(out_terms) == 49
        run('--task-at',campaign,1)
        assert (base/'recipes'/new_pin.decode().strip()).read_bytes() == plan
        assert (campaign/'composition/objects'/f'{result[2]}.tensor').read_bytes() == body

        # The old active sweep finishes before a newer library is coalesced.
        run('--sweep',campaign)
        second = read_record(q,'tasks',int((q/'submitted').read_text())).decode().split()
        assert second[-1] == '3137' and second[1] != context
        assert (base/'contexts'/second[1]).read_text().split()[2] == library_pin
        # Context/library mutations are rejected even if the source is valid.
        (base/'libraries'/library_pin).write_bytes(snapshot+b'\n')
        run('--task-at',campaign,1,ok=False)
        (base/'libraries'/library_pin).write_bytes(snapshot)
        (base/'contexts'/context).write_bytes(ctx+b'\n')
        run('--task-at',campaign,1,ok=False)
        (base/'contexts'/context).write_bytes(ctx)
        (campaign/'stop').touch()
        run('--sweep',campaign,ok=False)
    print('PASS native upstream: automatic 64->49, frozen legacy plan, pinned snapshots, cursor/crash replay, high-water deferral and mutation gates')


if __name__ == '__main__':
    check(str(Path(sys.argv[1]).resolve()),
          str(Path(sys.argv[2]).resolve()) if len(sys.argv)>2 else None)
