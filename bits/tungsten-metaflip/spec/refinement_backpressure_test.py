#!/usr/bin/env python3
"""Bounded exact queue: defer expansion, drain, and resume without lost input."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

from composition_queue_test import RUNTIME, audit, naive, store, value
from packed_composition_parity_test import parse_terms


def check(binary, external):
    env = dict(os.environ, METAFLIP_COMPOSITION_PENDING='1269',
               METAFLIP_COMPOSITION_FIFO='0', METAFLIP_COMPOSITION_MIXED='0')

    def run(*args, expected=0, unlimited=False):
        options = dict(env)
        if unlimited:
            options['METAFLIP_COMPOSITION_PENDING'] = '0'
        result = subprocess.run([str(binary), *map(str,args)], env=options,
                                text=True, capture_output=True, timeout=60)
        assert result.returncode == expected, (args,result.stdout,result.stderr)
        return result.stdout

    print(run().strip())
    with tempfile.TemporaryDirectory(prefix='metaflip-backpressure-test-') as d:
        base = Path(d); frozen = base/'frozen'
        for name in ('objects','tasks','results','by-id'):
            (frozen/name).mkdir(parents=True)
        terms = naive((2,2,2))
        for copies in range(103):
            identity = store(frozen,(2,2,2),terms+[terms[0]]*(2*copies))
            run('--prepare',frozen,RUNTIME,identity)
        assert value(frozen/'composition/submitted') == 927
        source = store(frozen,(4,8,4),parse_terms(Path(external).read_bytes(),94))
        (frozen/'tasks/1').write_text(source+'\n')
        before = set((frozen/'objects').iterdir())
        for _ in range(2):
            out = run('--refine-batch',frozen,1,1,RUNTIME)
            assert 'reason=composition-backpressure' in out
            assert not (frozen/'results/1').exists()
            assert value(frozen/'composition/submitted') == 927
            assert value(frozen/'composition/consumed') == 0
            assert set((frozen/'objects').iterdir()) == before
            assert (frozen/'backpressure').read_text() == 'MFR_PRESSURE1 1 360\n'
            assert not (frozen/'composition/error').exists()
        # Eight task records survive a lost submission cursor. Ignoring them
        # would appear to leave 360 slots; their real occupancy exceeds the
        # limit by one, so expansion must still wait.
        root = base/'lost-submitted'; shutil.copytree(frozen,root)
        for _ in range(4):
            run('--compose-batch',root,4)
        run('--compose-batch',root,1)
        assert value(root/'composition/consumed') == 17
        (root/'composition/submitted').write_text('919\n')
        out = run('--refine-batch',root,1,1,RUNTIME)
        assert 'reason=composition-backpressure' in out
        assert not (root/'results/1').exists()
        assert value(root/'composition/submitted') == 919
        # A genuine source error must not inherit an old resource-pause
        # marker and get mistaken for a successful deferred batch.
        root = base/'bad-source'; shutil.copytree(frozen,root)
        (root/'tasks/1').write_text('0'*64+'\n')
        out = run('--refine-batch',root,1,1,RUNTIME,expected=1)
        assert 'METAFLIP_REFINE_FAILED' in out and not (root/'backpressure').exists()
        # A two-source batch may commit its first result and defer its second.
        # Neither the first result nor either input ticket may disappear.
        root = base/'partial-batch'; shutil.copytree(frozen,root)
        for _ in range(9):
            run('--compose-batch',root,4)
        parent_terms = parse_terms(Path(external).read_bytes(),94)
        second = store(root,(4,8,4),parent_terms+[parent_terms[0]]*2)
        (root/'tasks/2').write_text(second+'\n')
        out = run('--refine-batch',root,1,2,RUNTIME)
        assert 'METAFLIP_REFINE_COMPLETED job=1' in out
        assert 'METAFLIP_REFINE_PENDING job=2' in out
        assert (root/'results/1').exists() and not (root/'results/2').exists()
        assert (root/'backpressure').read_text() == 'MFR_PRESSURE1 2 360\n'
        assert (root/'tasks/1').read_text() == source+'\n'
        assert (root/'tasks/2').read_text() == second+'\n'
        assert value(root/'composition/submitted')-value(root/'composition/consumed') <= 1269
        audit(root)
        # Unlimited is an explicit matched-control setting, not the default.
        root = base/'unlimited'; shutil.copytree(frozen,root)
        run('--refine-batch',root,1,1,RUNTIME,unlimited=True)
        assert (root/'results/1').exists() and not (root/'backpressure').exists()
        audit(root)
        # Coordinator must drain despite having an outstanding source job.
        root = base/'coordinator'; shutil.copytree(frozen,root)
        out = run('--coordinator',root,RUNTIME)
        assert 'PASS backpressure coordinator' in out
        assert value(root/'consumed') == 1
        assert value(root/'composition/consumed') >= 20
        assert value(root/'composition/submitted')-value(root/'composition/consumed') <= 1269
        assert (root/'tasks/1').read_text() == source+'\n'
        assert (root/'results/1').exists() and not (root/'backpressure').exists()
        audit(root)
        processes = subprocess.check_output(['ps','-axo','pid=,command='],text=True)
        assert not any(str(root) in line and ('--refine-batch' in line or '--compose-batch' in line)
                       for line in processes.splitlines())
        print(out.strip())
    print('PASS backpressure: no expansion/acknowledgement while blocked; exact drain and durable resume')


if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve(),Path(sys.argv[2]))
