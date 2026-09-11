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
from packed_composition_parity_test import naive
from verify_representation_portfolio import parse_terms
from composition_queue_test import audit as audit_composition
from composition_queue_test import value
from mixed_composition_queue_test import mixed_audit, deferred
from wide_composition_refinement_test import audit as audit_wide
from wide_transform_queue_test import audit as audit_transforms
from wide_feedback_test import audit as audit_feedback


def run(binary, root, tensor, enabled, seconds=2, require_outputs=True, extra=()):
    root.mkdir(parents=True, exist_ok=True)
    status = root/'status.txt'
    best = root/'best.txt'
    command = ['nice', '-n', '10', str(binary), '--tensor', tensor, '-J', '1',
               '--no-gpu', '--no-tui', '--quiet', '--secs', str(seconds),
               '--rounds', '1000000000', '--steps', '65536',
               '--state-dir', str(root/'state'), '--run-tag', 'refinement-test',
               '--status', str(status), '--best', str(best), *extra]
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
        assert int(fields['compose_wide_status']) in (0,1,2,3)
        assert 0 <= int(fields['compose_wide_saved']) <= 16384
        wide = dict(records=0, improved=0, limited=0)
        if (spool/'composition/cleanup/results').exists():
            wide = audit_wide(spool)
            last = list(map(int, (spool/'composition/cleanup/last').read_text().split()))
            assert last == [int(fields['compose_wide_status']), int(fields['compose_wide_saved'])]
        transforms = spool/'composition/transforms'
        assert int(fields['wide_transform_enabled']) == 1
        assert int(fields['wide_transform_submitted']) == value(transforms/'submitted')
        assert int(fields['wide_transform_completed']) == value(transforms/'consumed')
        assert int(fields['wide_transform_pending']) == value(transforms/'submitted')-value(transforms/'consumed')
        assert int(fields['wide_transform_failures']) == value(transforms/'failures') == 0
        assert int(fields['wide_transform_status']) in (0,1,2,3)
        transform_checks = audit_transforms(spool)
        feedback_checks = audit_feedback(spool)
        assert int(fields['wide_feedback_enabled'])==1
        assert int(fields['wide_feedback_failures'])==0
        assert 0<=int(fields['wide_feedback_seed_uses'])<=int(fields['refine_seed_uses'])
        assert int(fields['wide_feedback_submitted'])==feedback_checks['submitted']
        assert int(fields['wide_feedback_completed'])==feedback_checks['consumed']
        assert int(fields['wide_feedback_pending'])==feedback_checks['pending']
        assert int(fields['wide_feedback_offered'])>=0 and int(fields['wide_feedback_loaded'])>=0
        if (transforms/'last').exists():
            last = list(map(int,(transforms/'last').read_text().split()))
            assert last == [int(fields['wide_transform_status']),int(fields['wide_transform_delta'])]
        print(f'PASS fleet {tensor}: {objects} full tensors; '
              f'{fields["refine_seed_uses"]} seed uses; '
              f'{fields["refine_completed"]}/{fields["refine_submitted"]} jobs; '
              f'{fields["compose_completed"]}/{fields["compose_submitted"]} compositions; '
              f'{len(mixed)} mixed outputs, {fields["compose_deferred"]} deferred contexts; '
              f'{wide} wide cleanup; {transform_checks} wide transforms; '
              f'{feedback_checks} wide feedback; stopped')
    else:
        assert not spool.exists()
        assert int(fields['refine_submitted']) == int(fields['refine_outputs']) == 0
        print(f'PASS fleet {tensor}: disabled refinement leaves no spool')
    return fields


def check_at(binary, root):
    square = run(binary, root/'square', '5x5', 1)
    assert int(square['refine_seed_uses']) > 0, square
    assert int(square['compose_completed']) > 0, square
    first = run(binary, root/'rect', '2x5x6', 1)
    resumed = run(binary, root/'rect', '2x5x6', 1, seconds=1, require_outputs=False)
    assert int(resumed['refine_completed']) >= int(first['refine_completed'])
    assert int(resumed['refine_duplicates']) > 0
    run(binary, root/'disabled', '2x5x6', 0, seconds=1)
    # A cross-shape feedback slot spooled for this shape under the shared state
    # root is admitted only through the campaign's own exact loader (square
    # near bank; rectangular side archive) and reported as wide_feedback_loaded.
    # Slots are rank+1 term splits of packaged seeds: no rank-record claim.
    seeds = Path(__file__).resolve().parents[1]/'lib/metaflip/seeds/gf2'
    def split(terms, axis):
        index = next(i for i, term in enumerate(terms) if term[axis] & (term[axis]-1))
        term = list(terms[index]); low = term[axis] & -term[axis]
        rest = list(term); rest[axis] ^= low; term[axis] = low
        return terms[:index] + [tuple(term), tuple(rest)] + terms[index+1:]
    def spool(case, shape, slots):
        for slot, (name, rank, axes) in enumerate(slots):
            terms = parse_terms((seeds/name).read_bytes(), rank)
            for axis in axes:
                terms = split(terms, axis)
            exact(shape, terms)
            path = case/'state/banks/gf2'/('%dx%dx%d' % shape)/f'feedback/feedback_0{slot}.txt'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f'{len(terms)}\n' + ''.join(f'{u} {v} {w}\n' for u, v, w in sorted(terms)))
    # Algebraic +1 escapes of the packaged leader already fill near1 (a single
    # Strassen split is a duplicate there), so spool a different packaged
    # basin's split and a rank+2 double split: distinct exact tensors.
    spool(root/'square-feedback', (2, 2, 2), [('matmul_2x2_rank7_d36_gl120_gf2.txt', 7, [1]),
                                              ('matmul_2x2_rank7_strassen_gf2.txt', 7, [1, 0])])
    fed = run(binary, root/'square-feedback', '2x2', 1, require_outputs=False)
    assert int(fed['wide_feedback_loaded']) == 2, fed
    assert int(first['wide_feedback_loaded']) == 0 and int(square['wide_feedback_loaded']) == 0
    spool(root/'rect-feedback', (2, 5, 6), [('matmul_2x5x6_rank47_catalog_gf2.txt', 47, [1])])
    fed = run(binary, root/'rect-feedback', '2x5x6', 1, require_outputs=False, extra=('--rect-door-ticket', '0'))
    assert int(fed['wide_feedback_loaded']) == 1, fed
    assert int(fed['side_archive_loaded']) == 1, fed
    # A spooled slot strictly below the loaded best crosses the checkpoint
    # gate and becomes the starting best, also for an unsalted explicit --seed
    # start that loads no side archive. Start from the 28-term naive 2x2x7
    # scheme (the packaged rank-26 door is cleaned to 25 at the anchor gate)
    # and spool the packaged rank-25 seed. No rank-record claim.
    case = root/'rect-spool-best'
    case.mkdir(parents=True)
    start = case/'naive_2x2x7.txt'
    terms = naive((2, 2, 7))
    exact((2, 2, 7), terms)
    start.write_text(f'{len(terms)}\n' + ''.join(f'{u} {v} {w}\n' for u, v, w in terms))
    spool(case, (2, 2, 7), [('matmul_2x2x7_rank25_d128_rect_portfolio_gf2.txt', 25, [])])
    fed = run(binary, case, '2x2x7', 1, require_outputs=False, extra=('--seed', str(start)))
    assert int(fed['best_rank']) == 25 and int(fed['wide_feedback_loaded']) == 1, fed
    assert int(fed['side_archive_loaded']) == 0, fed


def check(binary, retained=None):
    if retained is not None:
        root = Path(retained)
        assert not root.exists()
        root.mkdir(parents=True)
        check_at(binary, root)
    else:
        with tempfile.TemporaryDirectory(prefix='metaflip-refinement-fleet-') as directory:
            check_at(binary, Path(directory))


if __name__ == '__main__':
    check(Path(sys.argv[1]).resolve(), sys.argv[2] if len(sys.argv)>2 else None)
