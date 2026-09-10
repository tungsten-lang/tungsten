#!/usr/bin/env python3
"""Automatic post-composition cleanup, immutable originals and full gates."""
from hashlib import sha256
from pathlib import Path
import subprocess
import sys
import tempfile

from composition_queue_test import read_record
from wide_matrix_cleanup_parity_test import blob, read_blob, same_tensor
from packed_composition_parity_test import exact
from verify_cofactor_mergers import compress_shared


def audit(root):
    q = Path(root)/'composition'
    records = list((q/'cleanup/results').iterdir())
    counts = dict(records=0, improved=0, limited=0)
    for path in records:
        raw = path.read_bytes()
        fields = raw.decode().split()
        assert len(fields) == 12 and raw == (' '.join(fields)+'\n').encode()
        tag, source, result, shape, before, proposed, after, status, work, axes, groups, saved = fields
        assert tag == 'MFW_CLEAN1' and path.name == source
        before, proposed, after, status, work, axes, groups, saved = map(
            int, (before, proposed, after, status, work, axes, groups, saved))
        shape = tuple(map(int, shape.split('x')))
        first = (q/'objects'/f'{source}.tensor').read_bytes()
        last = (q/'objects'/f'{result}.tensor').read_bytes()
        assert sha256(first).hexdigest() == source and sha256(last).hexdigest() == result
        ss, source_terms = read_blob(first)
        rs, result_terms = read_blob(last)
        assert ss == rs == shape and len(source_terms) == before and len(result_terms) == after
        assert status in (1, 2, 3) and 0 <= work <= 20000000
        assert 0 <= saved <= before-proposed and 0 <= groups <= before
        assert 1 <= proposed <= before and 1 <= after <= before
        exact(shape, source_terms)
        exact(shape, result_terms)
        same_tensor(source_terms, result_terms)
        if status == 1:
            expected, _ = compress_shared(source_terms, max_bits=max(a*b for a,b in
                ((shape[0],shape[1]), (shape[1],shape[2]), (shape[0],shape[2]))))
            assert result_terms == sorted(expected) and proposed == after
        elif status == 2:
            assert proposed == after
        else:
            assert after == before and result == source
        counts['records'] += 1
        counts['improved'] += after < before
        counts['limited'] += status != 1
    return counts


def check(binary):
    binary = str(Path(binary).resolve())
    with tempfile.TemporaryDirectory(prefix='metaflip-wide-admission-') as directory:
        root = Path(directory)
        shape = (1, 1, 65)
        source = [(1, 1 << i, 1 << i) for i in range(1, 64)]
        source += [(1, 1 << 64, 1), (1, 1, 1 << 64), (1, (1 << 64)+1, (1 << 64)+1)]
        first = blob(shape, source)
        src = root/'source.tensor'; src.write_bytes(first)
        key = sha256(first).hexdigest()

        def run(ok=True):
            child = subprocess.run([binary, '--finish-wide', str(root), str(src)],
                                   capture_output=True, text=True, timeout=60)
            assert (child.returncode == 0) == ok, (child.returncode, child.stdout, child.stderr)
            return child

        # A stop cannot acknowledge a job or create a cleanup manifest.
        (root/'stop').write_text('stop\n')
        run(False)
        q = root/'composition'
        assert read_record(q, 'results', 1) is None
        assert not (q/'cleanup/results').exists()
        (root/'stop').unlink()
        run()
        counts = audit(root)
        assert counts == dict(records=1, improved=1, limited=0)
        record = q/'cleanup/results'/key
        fields = record.read_text().split()
        output = fields[2]
        assert fields[4:8] == ['66', '65', '65', '1']
        assert (q/'objects'/f'{key}.tensor').read_bytes() == first
        assert (q/'best/1x1x65').read_text() == f'65 {output}\n'
        completion = read_record(q, 'results', 1)
        assert completion.split()[3:] == [key.encode(), b'1x1x65', b'66']
        saved = {p:p.read_bytes() for p in q.rglob('*') if p.is_file()}
        run()
        assert saved == {p:p.read_bytes() for p in q.rglob('*') if p.is_file()}

        # The original tensor gate precedes cleanup and archive writes.
        bad = list(source); u,v,w = bad[0]; bad[0] = (u,v,w ^ 1)
        src.write_bytes(blob(shape, bad)); run(False); src.write_bytes(first)
        assert saved == {p:p.read_bytes() for p in q.rglob('*') if p.is_file()}

        good_record = record.read_bytes()
        record.write_bytes(good_record+b' ')
        run(False); record.write_bytes(good_record)
        # A rehashed false output is not admitted by the cache.
        good_output = (q/'objects'/f'{output}.tensor').read_bytes()
        _, terms = read_blob(good_output)
        bad = terms.copy(); u,v,w = bad[0]; bad[0] = (u,v,w ^ 2)
        false_blob = blob(shape, bad); false_key = sha256(false_blob).hexdigest()
        false_path = q/'objects'/f'{false_key}.tensor'; false_path.write_bytes(false_blob)
        altered = fields.copy(); altered[2] = false_key
        record.write_text(' '.join(altered)+'\n')
        run(False)
        assert read_record(q, 'results', 1) == completion
        assert (q/'best/1x1x65').read_text() == f'65 {output}\n'
        record.write_bytes(good_record); false_path.unlink()
        # Missing and corrupted cached witnesses are failures, not dedup hits.
        output_path = q/'objects'/f'{output}.tensor'
        output_path.unlink(); run(False)
        output_path.write_bytes(good_output+b' '); run(False)
        output_path.write_bytes(good_output)
        run(); assert audit(root) == counts
        print('PASS automatic wide cleanup: 66->65, originals/replay preserved, stop and forged/missing tensor gates')


if __name__ == '__main__':
    check(sys.argv[1])
