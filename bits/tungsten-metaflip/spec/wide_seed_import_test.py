#!/usr/bin/env python3
"""Independent import policy and every packaged wide seed; no network."""
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('wide_import', ROOT/'tools/import_wide_seeds.py')
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)


class WideImportTest(unittest.TestCase):
    def test_field_gate(self):
        self.assertEqual([importer.parity(v) for v in (0, 1, -1, '1/3', '2/3')], [0, 1, 1, 1, 0])
        for value in ('1/2', '1/8', 0.5, True, 'nan', '__import__("os")'):
            with self.assertRaises(ValueError):
                importer.parity(value)

    def test_circuit_references(self):
        for index in (-1, 2, True):
            with self.assertRaises(ValueError):
                importer.circuit({'u': [[{'index': index, 'value': 1}]]}, 'u', 1, 2)

    def test_source_hash_fails_before_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = next(iter(importer.SOURCES))
            cached = root/'cache'/importer.COMMIT/'schemes/results'/source
            cached.parent.mkdir(parents=True)
            cached.write_bytes(b'{}')
            with patch.dict(importer.SOURCES, {source: importer.SOURCES[source]}, clear=True):
                with self.assertRaisesRegex(ValueError, 'git-blob hash mismatch'):
                    importer.run(root/'cache', root/'runtime')
            self.assertFalse((root/'runtime').exists())

    def test_catalog_and_independent_ruby_replay(self):
        rows = list(csv.DictReader((ROOT/'lib/metaflip/manifests/wide-seeds.tsv').read_text().splitlines(), delimiter='\t'))
        self.assertEqual(len(rows), 12)
        self.assertEqual({int(row['square']) for row in rows}, set(range(8, 17)))
        identities = set()
        for row in rows:
            path = ROOT/'lib/metaflip'/row['runtime_path']
            raw = path.read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), row['certificate_sha256'])
            self.assertEqual(row['commit'], importer.COMMIT)
            self.assertEqual(row['license'], 'MIT')
            self.assertNotIn(row['certificate_sha256'], identities)
            identities.add(row['certificate_sha256'])
            n = int(row['square'])
            result = subprocess.run(['ruby', str(ROOT/'tools/verify_tensor.rb'), '--shape', f'{n}x{n}x{n}', str(path)],
                                    check=True, capture_output=True, text=True, timeout=30)
            checked = json.loads(result.stdout)[0]
            self.assertTrue(checked['exact'])
            self.assertEqual(checked['rank'], int(row['rank']))
            self.assertEqual(checked['density'], int(row['density']))
            print(f'Ruby EXACT {n}x{n}: rank {row["rank"]}', flush=True)

    def test_tampered_tensor_and_dimensions(self):
        rows = list(csv.DictReader((ROOT/'lib/metaflip/manifests/wide-seeds.tsv').read_text().splitlines(), delimiter='\t'))
        path = ROOT/'lib/metaflip'/rows[0]['runtime_path']
        raw = path.read_text().splitlines()
        n = int(raw[0].split()[1])
        terms = [tuple(int(v, 16) for v in row.split()) for row in raw[1:]]
        importer.verify(n, terms)
        u, v, w = terms[0]
        terms[0] = (u, v, w ^ 1)
        with self.assertRaises(ValueError):
            importer.verify(n, terms)
        with self.assertRaises(ValueError):
            importer.decode({'n': [8, 8, 8], 'm': 1, 'commutative': True})


if __name__ == '__main__':
    unittest.main()
