#!/usr/bin/env python3
"""Native packed intake/feedback gates; fixtures are not record claims."""
from hashlib import sha256
from pathlib import Path
import subprocess
import sys
import tempfile

from wide_matrix_cleanup_parity_test import blob
from packed_composition_parity_test import naive, exact
from composition_queue_test import read_record


def fields(output):
    return dict(word.split('=', 1) for word in output.split() if '=' in word)


def check(binary):
    def run(*args):
        result = subprocess.run([binary, *map(str, args)], text=True,
                                capture_output=True, timeout=30)
        assert result.returncode == 0, result.stdout + result.stderr
        return result.stdout

    with tempfile.TemporaryDirectory(prefix='metaflip-packed-refinement-') as tmp:
        root = Path(tmp)
        terms = naive((8, 8, 8))
        source = root/'source.mfw'
        source.write_bytes(blob((8, 8, 8), terms))
        # Exact +1 term split with a nontrivial shared (V,W) matrix cleanup.
        u, v, w = terms[0]
        split = sorted([(u ^ (1 << 63), v, w), (1 << 63, v, w)] + terms[1:])
        exact((8, 8, 8), split)
        expanded = root/'expanded.mfw'
        expanded.write_bytes(blob((8, 8, 8), split))
        queue = root/'intake'
        run('--submit', queue, expanded)
        run('--submit', queue, expanded)
        assert (queue/'composition/packed-intake/submitted').read_text() == '1\n'
        # Dedup is invariant under term order; callers keep their slab intact.
        reversed_source = root/'reversed.mfw'
        reversed_source.write_bytes(blob((8, 8, 8), list(reversed(split))))
        run('--submit', queue, reversed_source)
        assert (queue/'composition/packed-intake/submitted').read_text() == '1\n'
        run('--compose-batch', queue, 1)
        assert (queue/'composition/packed-intake/consumed').read_text() == '1\n'
        task = read_record(queue/'composition/transforms', 'tasks', 1).decode().split()
        assert task[-1] == '3135'
        clean = (queue/'composition/cleanup/results'/task[1]).read_text().split()
        assert list(map(int, clean[4:7])) == [513, 512, 512], clean
        state = fields(run('--take', queue, 8))
        assert state['rank'] == '512' and state['packed_failures'] == '0', state
        # Subsequent calls acknowledge the same candidate exactly once.
        assert fields(run('--take', queue, 8))['rank'] == '0'

        # Root high-water backpressure retains an unacknowledged input.
        blocked = root/'blocked'
        run('--submit', blocked, source)
        transforms = blocked/'composition/transforms'
        transforms.mkdir()
        (transforms/'submitted').write_text('256\n')
        run('--schedule', blocked, 'unused')
        assert not (blocked/'composition/packed-intake/consumed').exists()
        (transforms/'submitted').write_text('0\n')
        run('--schedule', blocked, 'unused')
        assert (blocked/'composition/packed-intake/consumed').read_text() == '1\n'
        # A crash after scheduling but before intake acknowledgement must
        # not enqueue the same root twice.
        (blocked/'composition/packed-intake/consumed').write_text('0\n')
        run('--schedule', blocked, 'unused')
        assert (transforms/'submitted').read_text() == '1\n'

        # Recover a producer stopped after task+index but before submitted.
        recovery = root/'recovery'
        run('--publish', recovery, source)
        outbox = recovery/'composition/packed-feedback'
        (outbox/'submitted').write_text('0\n')
        run('--publish', recovery, source)
        assert (outbox/'submitted').read_text() == '1\n'
        assert fields(run('--take', recovery, 8))['rank'] == '512'

        # Full bytes matter at equal rank; two presentations get two tickets.
        ties = root/'ties'
        run('--publish', ties, source)
        # Simultaneous row-basis shear: U'=M U and W'=M^-T W.
        def shear(word, inverse_transpose):
            out = word
            for col in range(8):
                if inverse_transpose:
                    out ^= ((word >> col) & 1) << (8 + col)
                else:
                    out ^= ((word >> (8 + col)) & 1) << col
            return out
        alternate = sorted((shear(u, False), v, shear(w, True)) for u, v, w in terms)
        exact((8, 8, 8), alternate)
        tied = root/'tie.mfw'
        tied.write_bytes(blob((8, 8, 8), alternate))
        run('--publish', ties, tied)
        assert (ties/'composition/packed-feedback/submitted').read_text() == '2\n'
        assert fields(run('--take', ties, 8))['rank'] == '512'
        assert fields(run('--take', ties, 8))['rank'] == '512'

        # Other live shapes are offered to a persistent, bounded seed bank.
        cross = root/'cross'
        run('--publish', cross, source)
        shared_state = root/'state'
        state = fields(run('--take', cross, 9, shared_state))
        assert state['rank'] == '0' and state['packed_cross_shape'] == '1'
        offered = list((shared_state/'banks/gf2/8x8x8/packed-feedback').glob('*.mfw'))
        assert len(offered) == 1 and offered[0].read_bytes() == source.read_bytes()

        # Small descendants use the existing exact narrow seed boundary.
        small = root/'small.mfw'
        small.write_bytes(blob((3, 3, 3), naive((3, 3, 3))))
        narrow_queue = root/'narrow'
        run('--publish', narrow_queue, small)
        state = fields(run('--take', narrow_queue, 8, shared_state))
        assert state['rank'] == '0' and state['packed_cross_shape'] == '1'
        assert list((shared_state/'banks/gf2/3x3x3/feedback').glob('*.txt'))

        # A hash-valid but inexact object must not pass the consumer gate.
        invalid = root/'invalid'
        run('--publish', invalid, source)
        bad = blob((8, 8, 8), terms[:-1])
        bad_id = sha256(bad).hexdigest()
        obj = invalid/'composition/objects'/f'{bad_id}.tensor'
        obj.write_bytes(bad)
        outbox = invalid/'composition/packed-feedback'
        old_id = sha256(source.read_bytes()).hexdigest()
        record = read_record(outbox, 'tasks', 1).decode()
        # Rewrite a fixture's paged record and index consistently, not only
        # its hash: exact tensor reconstruction remains the deciding gate.
        page = next((outbox/'tasks-pages').glob('*'))
        header, body = page.read_text().split('\n', 1)
        body = body.replace(record, record.replace(old_id, bad_id).replace('512\n', '511\n'))
        tag, first, count, _ = header.split()
        page.write_text(f'{tag} {first} {count} {sha256(body.encode()).hexdigest()}\n' + body)
        (outbox/'by-id'/bad_id).write_text('1\n')
        state = fields(run('--take', invalid, 8))
        assert state['rank'] == '-1' and state['packed_failures'] == '1', state
        assert not (outbox/'consumed').exists()
    print('PASS packed cleanup/reseed, full-term ties, dedup, high-water deferral, crash recovery, cross-shape spool and exact rejection')


if __name__ == '__main__':
    check(str(Path(sys.argv[1]).resolve()))
