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
            else:
                assert not queue.exists()
                assert f['packed_tasks'] == f['packed_seed_uses'] == '0', f
            print(f'PASS packed live refine={enabled}: moves={f["cpu_moves"]}; '
                  f'completed={f["packed_completed"]}; seeds={f["packed_seed_uses"]}; stopped')


if __name__ == '__main__':
    check(str(Path(sys.argv[1]).resolve()), str(Path(sys.argv[2]).resolve()))
