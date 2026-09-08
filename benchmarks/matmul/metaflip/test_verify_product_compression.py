import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from verify_product_compression import check_row, digest, source_entries, verify


class ProductCompressionTest(unittest.TestCase):
    def run_fixture(self, flat=False):
        with tempfile.TemporaryDirectory(prefix='metaflip-compression-test-') as directory:
            root = Path(directory);source = root/'source';source.mkdir()
            entries = []
            for shape in ((1,2,2), (1,2,257)):
                n,m,p = shape
                terms = [(1 << (i*m+j), 1 << (j*p+k), 1 << (i*p+k))
                         for i in range(n) for j in range(m) for k in range(p)]
                terms += [terms[-1], terms[-1]]
                body = (str(len(terms))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in terms)).encode()
                name = 'x'.join(map(str,shape))+'.txt';(source/name).write_bytes(body)
                entry = dict(path=name, shape=shape, sha256=digest(body))
                if flat:
                    entry['rank'] = len(terms)
                entries.append(entry)
            prior = dict(complete=True, field='GF(2)', record_claim=False,
                         outputs=entries if flat else [dict(result=e) for e in entries])
            raw = (json.dumps(prior)+'\n').encode();(source/'report.json').write_bytes(raw)
            audit = dict(complete=True, field='GF(2)', record_claim=False,
                         report_sha256=digest(raw), source_sha256={e['path']:e['sha256'] for e in entries})
            (source/'independent-audit.json').write_text(json.dumps(audit)+'\n')
            repo = Path(__file__).resolve().parents[3]
            tool = repo/'bits/tungsten-metaflip/tools/compress_checked_products.rb'
            out = root/'output'
            run = subprocess.run(['ruby', str(tool), str(source), str(out)],
                                 capture_output=True, text=True, check=False)
            self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
            result = verify(out, workers=1)
            self.assertEqual(result['changed'], 2)
            self.assertEqual(result['rank_saved'], 4)
            self.assertEqual(result['tensors'], 4)
            report = json.loads((out/'report.json').read_text())
            bad = copy.deepcopy(report['rows'][0]);bad['rank_after'] += 1
            self.assertRaises(AssertionError, check_row, (out,bad))
            bad = copy.deepcopy(report['rows'][1]);bad['max_bits'] = 256
            self.assertRaises(AssertionError, check_row, (out,bad))
            # Substituting a separately valid input must fail source identity.
            bad_report = copy.deepcopy(report)
            bad_report['rows'][0]['input'] = report['rows'][1]['input']
            (out/'report.json').write_text(json.dumps(bad_report)+'\n')
            self.assertRaises(AssertionError, verify, out, workers=1)
            if flat:
                # Even repinned metadata must agree with the actual snapshot.
                prior['outputs'][0]['rank'] += 1
                report['rows'][0]['source']['rank'] += 1
                raw = (json.dumps(prior)+'\n').encode()
                audit['report_sha256'] = digest(raw)
                audit_raw = (json.dumps(audit)+'\n').encode()
                report['source_report_sha256'] = digest(raw)
                report['source_audit_sha256'] = digest(audit_raw)
                (out/'source-report.json').write_bytes(raw)
                (out/'source-audit.json').write_bytes(audit_raw)
                (out/'report.json').write_text(json.dumps(report)+'\n')
                self.assertRaises(AssertionError, verify, out, workers=1)
                (source/'report.json').write_bytes(raw)
                (source/'independent-audit.json').write_bytes(audit_raw)
                run = subprocess.run(['ruby', str(tool), str(source), str(root/'bad-rank')],
                                     capture_output=True, text=True, check=False)
                self.assertNotEqual(run.returncode, 0)
                self.assertIn('source rank mismatch', run.stderr)
                # A malformed wrapped output cannot masquerade as a flat one.
                prior['outputs'][0]['result'] = None
                raw = (json.dumps(prior)+'\n').encode()
                audit['report_sha256'] = digest(raw)
                (source/'report.json').write_bytes(raw)
                (source/'independent-audit.json').write_text(json.dumps(audit)+'\n')
                run = subprocess.run(['ruby', str(tool), str(source), str(root/'bad-result')],
                                     capture_output=True, text=True, check=False)
                self.assertNotEqual(run.returncode, 0)
                self.assertIn('missing source snapshot', run.stderr)

    def test_ruby_producer_independent_replay_and_corruption(self):
        self.run_fixture()

    def test_flat_projection_replay_and_rank_corruption(self):
        self.run_fixture(flat=True)

    def test_present_result_never_falls_back_to_flat_snapshot(self):
        entry = dict(shape=[1,2,2], path='input.txt', sha256='a'*64, rank=4)
        self.assertEqual(source_entries(dict(outputs=[entry, dict(result=entry)])), [entry, entry])
        for result in (None, [], 0, False):
            with self.subTest(result=result):
                self.assertRaises(AssertionError, source_entries,
                                  dict(outputs=[dict(entry, result=result)]))


if __name__ == '__main__':
    unittest.main()
