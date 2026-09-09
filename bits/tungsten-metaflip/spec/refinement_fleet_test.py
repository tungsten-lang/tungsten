#!/usr/bin/env python3
"""Bounded CPU-only public-binary integration; no record/performance claim."""
from hashlib import sha256
from pathlib import Path
import os
import signal
import subprocess
import sys
import tempfile

from refinement_worker_parity_test import exact
from verify_representation_portfolio import parse_terms
from composition_queue_test import audit as audit_composition
from composition_queue_test import value
from mixed_composition_queue_test import mixed_audit, deferred


def run(binary, root, tensor, enabled, seconds=2, require_outputs=True):
    root.mkdir(parents=True, exist_ok=True)
    status = root/'status.txt'
    best = root/'best.txt'
    command = ['nice', '-n', '10', str(binary), '--tensor', tensor, '-J', '1',
               '--no-gpu', '--no-tui', '--quiet', '--secs', str(seconds),
               '--rounds', '1000000000', '--steps', '65536',
               '--state-dir', str(root/'state'), '--run-tag', 'refinement-test',
               '--status', str(status), '--best', str(best)]
    env = dict(os.environ, METAFLIP_REFINEMENT=str(enabled),
               METAFLIP_COMPOSITION_MIXED='1',
               OMP_NUM_THREADS='1', OPENBLAS_NUM_THREADS='1',
               VECLIB_MAXIMUM_THREADS='1')
    proc = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        output, _ = proc.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGINT)
        try:
            proc.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate()
        raise
    assert proc.returncode == 0, output
    fields = dict(token.split('=', 1) for token in status.read_text().split() if '=' in token)
    assert fields['producer_state'] in ('DONE', 'stopped'), fields
    assert int(fields['refine_failures']) == 0, fields
    assert int(fields['refine']) == enabled, fields
    shape = tuple(map(int, tensor.split('x')))
    if len(shape) == 2:
        shape += (shape[-1],)
    exact(shape, parse_terms(best.read_bytes(), int(fields['best_rank'])))
    spool = Path(str(status)+'.refinement')
    if enabled:
        assert int(fields['refine_submitted']) > 0
        assert int(fields['refine_completed']) > 0
        if require_outputs:
            assert int(fields['refine_cross_shape']) > 0
        assert int(fields['refine_pending']) == int(fields['refine_submitted'])-int(fields['refine_completed'])
        assert (spool/'stop').is_file()
        assert int(fields['compose_failures']) == 0, fields
        assert int(fields['compose_pending']) == int(fields['compose_submitted'])-int(fields['compose_completed'])
        assert int(fields['compose_deferred']) == deferred(spool)
        assert int(fields['compose_submitted']) == value(spool/'composition/submitted')+value(spool/'composition/mixed/submitted')
        assert int(fields['compose_completed']) == value(spool/'composition/consumed')+value(spool/'composition/mixed/consumed')
        objects = 0
        for path in (spool/'objects').glob('*.tensor'):
            data = path.read_bytes()
            assert sha256(data).hexdigest() == path.stem
            lines = data.decode().splitlines()
            header = lines[0].split()
            dims = tuple(map(int, header[1:4]))
            terms = [tuple(map(int, line.split())) for line in lines[1:]]
            assert len(terms) == int(header[4]) and terms == sorted(terms)
            exact(dims, terms)
            objects += 1
        processes = subprocess.run(['ps', '-axo', 'pid=,command='], check=True,
                                   text=True, stdout=subprocess.PIPE).stdout
        assert not any(('--refine-batch' in line or '--compose-batch' in line) and str(spool) in line
                       for line in processes.splitlines()), processes
        composed = audit_composition(spool)
        mixed = mixed_audit(spool)
        print(f'PASS fleet {tensor}: {objects} full tensors; '
              f'{fields["refine_seed_uses"]} seed uses; '
              f'{fields["refine_completed"]}/{fields["refine_submitted"]} jobs; '
              f'{fields["compose_completed"]}/{fields["compose_submitted"]} compositions; '
              f'{len(mixed)} mixed outputs, {fields["compose_deferred"]} deferred contexts; stopped')
    else:
        assert not spool.exists()
        assert int(fields['refine_submitted']) == int(fields['refine_outputs']) == 0
        print(f'PASS fleet {tensor}: disabled refinement leaves no spool')
    return fields


def check(binary):
    with tempfile.TemporaryDirectory(prefix='metaflip-refinement-fleet-') as directory:
        root = Path(directory)
        square = run(binary, root/'square', '5x5', 1)
        assert int(square['refine_seed_uses']) > 0, square
        assert int(square['compose_completed']) > 0, square
        first = run(binary, root/'rect', '2x5x6', 1)
        resumed = run(binary, root/'rect', '2x5x6', 1, seconds=1, require_outputs=False)
        assert int(resumed['refine_completed']) >= int(first['refine_completed'])
        assert int(resumed['refine_duplicates']) > 0
        run(binary, root/'disabled', '2x5x6', 0, seconds=1)


if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve())
