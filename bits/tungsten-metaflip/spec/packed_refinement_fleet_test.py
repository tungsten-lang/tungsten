#!/usr/bin/env python3
"""Public binary lifecycle and tie feedback; no record/performance claim."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

from packed_refinement_test import fields
from packed_composition_parity_test import naive, exact
from wide_matrix_cleanup_parity_test import blob, read_blob
from composition_queue_test import read_record
from wide_closure_test import replay_native_recipe


def check(binary, helper):
    runtime = Path(__file__).resolve().parents[1]/'lib/metaflip'
    with tempfile.TemporaryDirectory(prefix='metaflip-packed-live-') as tmp:
        root = Path(tmp)
        terms = naive((8, 8, 8))
        source = root/'seed.mfw'
        source.write_bytes(blob((8, 8, 8), terms))
        def shear(word, dual):
            out = word
            for col in range(8):
                if dual:
                    out ^= ((word >> col) & 1) << (8 + col)
                else:
                    out ^= ((word >> (8 + col)) & 1) << col
            return out
        alternate = sorted((shear(u, False), v, shear(w, True)) for u, v, w in terms)
        exact((8, 8, 8), alternate)
        tied = root/'tie.mfw'
        tied.write_bytes(blob((8, 8, 8), alternate))
        for enabled in (1, 0):
            case = root/str(enabled)
            case.mkdir()
            status = case/'status.txt'
            best = case/'best.mfw'
            queue = Path(str(status)+'.refinement')
            if enabled:
                subprocess.run([helper, '--publish', str(queue), str(tied)],
                               check=True, capture_output=True, timeout=30)
            result = subprocess.run([
                binary, '--runtime-root', str(runtime), '--tensor', '8x8',
                '--seed', str(source), '--status', str(status), '--best', str(best),
                '--state-dir', str(case/'state'), '--no-tui', '--no-gpu', '--quiet',
                '-J', '2', '--steps', '100000', '--secs', '4'],
                env=dict(os.environ, METAFLIP_REFINEMENT=str(enabled)),
                capture_output=True, text=True, timeout=20)
            assert result.returncode == 0, result.stdout+result.stderr
            f = fields(status.read_text())
            assert f['producer_state'] == 'stopped' and f['exact_rejects'] == '0', f
            assert f['packed_failures'] == '0' and f['packed_refine'] == str(enabled), f
            assert int(f['cpu_moves']) > 0 and f['cpu_lanes'] == '2', f
            shape, got = read_blob(best.read_bytes())
            exact(shape, got)
            assert shape == (8, 8, 8) and len(got) <= 512
            if enabled:
                assert int(f['packed_intake']) > 0 and int(f['packed_completed']) > 0, f
                assert int(f['packed_seed_uses']) >= 1, f
                assert (queue/'stop').exists()
                # The public launcher supplies the relocatable catalogue
                # before any closure ticket freezes its witness recipe.
                transforms = queue/'composition/transforms'
                closure_rows = []
                for ticket in range(1, int((transforms/'consumed').read_text())+1):
                    task = read_record(transforms, 'tasks', ticket).decode().split()
                    result_fields = read_record(transforms, 'results', ticket).decode().split()
                    if task[-1] == '3136' and result_fields[2] != '-':
                        closure_rows.append((task, result_fields))
                assert closure_rows, (f, closure_rows)
                task, result_fields = closure_rows[0]
                recipe_shape, recipe_terms = replay_native_recipe(queue, task[1])
                exact(recipe_shape, recipe_terms)
                assert recipe_shape == tuple(map(int, result_fields[3:6]))
            else:
                assert not queue.exists()
                assert f['packed_tasks'] == f['packed_seed_uses'] == '0', f
            print(f'PASS packed live refine={enabled}: moves={f["cpu_moves"]}; '
                  f'completed={f["packed_completed"]}; seeds={f["packed_seed_uses"]}; stopped')

        # Separate from the pre-published tie fixture: allow the original
        # best's same-shape closure ticket to feed the public worker back.
        case = root/'closure-feedback'
        case.mkdir()
        result = subprocess.run([
            binary, '--runtime-root', str(runtime), '--tensor', '8x8',
            '--seed', str(source), '--status', str(case/'status'),
            '--best', str(case/'best'), '--state-dir', str(case/'state'),
            '--no-tui', '--no-gpu', '--quiet', '-J', '2', '--steps', '2050',
            '--secs', '6'], env=dict(os.environ, METAFLIP_REFINEMENT='1'),
            capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, result.stdout+result.stderr
        shape, got = read_blob((case/'best').read_bytes())
        exact(shape, got)
        f = fields((case/'status').read_text())
        assert shape == (8, 8, 8) and len(got) <= 329, f
        assert f['packed_failures'] == f['exact_rejects'] == '0', f
        assert int(f['packed_seed_uses']) >= 1 and f['producer_state'] == 'stopped', f
        print('PASS public native closure adopts exact 8x8x8/r329 while flipping')


if __name__ == '__main__':
    check(str(Path(sys.argv[1]).resolve()), str(Path(sys.argv[2]).resolve()))
