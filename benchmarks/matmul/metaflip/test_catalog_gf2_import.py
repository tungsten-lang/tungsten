#!/usr/bin/env python3
"""Small independent tensor fixtures for the catalog boundary, not live data."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

import catalog_gf2_import as importer


def naive_rectangular():
    n, m, p = 2, 2, 3
    data = dict(n=[n, m, p], m=n * m * p, fields=["F2"], verified=True, u=[], v=[], w=[])
    expected = []
    for i in range(n):
        for j in range(m):
            for k in range(p):
                for name, width, index in (("u", n * m, i * m + j), ("v", m * p, j * p + k),
                                           ("w", n * p, k * n + i)):
                    row = [0] * width
                    row[index] = 1
                    data[name].append(row)
                expected.append(f"R {1 << (i*m+j)} {1 << (j*p+k)} {1 << (i*p+k)}\n")
    return data, "".join(expected)


def sparse_version(data, keep_dense=False):
    result = copy.deepcopy(data)
    for name in ("u", "v", "w"):
        result[name + "_sparse"] = {
            str(index): {"i": [i for i, c in enumerate(row) if c], "c": [c for c in row if c]}
            for index, row in enumerate(result[name])
        }
        if not keep_dense:
            del result[name]
    return result


def circuit_version(data, nested=False):
    result = copy.deepcopy(data)
    rows = lambda matrix: [[dict(index=i, value=c) for i, c in enumerate(row) if c]
                           for row in matrix]
    result['u'] = rows(data['u'])
    result['v'] = rows(data['v'])
    result['w'] = rows(list(zip(*data['w'])))
    if nested:
        for name, width in [('u', len(data['u'][0])), ('v', len(data['v'][0])), ('w', data['m'])]:
            result[name + '_fresh'] = [
                [dict(index=0, value=1), dict(index=1, value=1)],
                [dict(index=width, value=1), dict(index=1, value=-1)]]
            for row in result[name]:
                for entry in row:
                    if entry['index'] == 0:
                        entry['index'] = width + 1
    return result


class CatalogImportTest(unittest.TestCase):
    def convert(self, data):
        with tempfile.TemporaryDirectory(prefix="catalog-test-") as root:
            source, output = Path(root) / "source.json", Path(root) / "output.txt"
            source.write_text(json.dumps(data))
            result = importer.convert(source, output)
            return result, output.read_text()

    def test_dense_sparse_and_consistent_dual_encodings_match_exact_expected_rows(self):
        dense, expected = naive_rectangular()
        for data in (dense, sparse_version(dense), sparse_version(dense, keep_dense=True)):
            with self.subTest(encoding=list(data)):
                result, actual = self.convert(data)
                self.assertEqual(((2, 2, 3), 12), result)
                self.assertEqual(expected, actual)

    def test_signed_integral_coefficients_reduce_modulo_two(self):
        data, expected = naive_rectangular()
        for name in ("u", "v", "w"):
            data[name] = [[-c for c in row] for row in data[name]]
        self.assertEqual(expected, self.convert(sparse_version(data))[1])

    def test_complete_expanded_sparse_factors_allow_unused_circuit_annotations(self):
        dense, expected = naive_rectangular()
        data = sparse_version(dense)
        data.update(u_fresh=[[dict(index=1, value=1)]], v_fresh=[], w_fresh=[])
        self.assertEqual(expected, self.convert(data)[1])
        data['u_sparse']['0']['i'] = [4]  # still input coordinates, not an intermediate
        with self.assertRaisesRegex(ValueError, 'outside factor width'):
            self.convert(data)

    def test_circuit_input_and_product_intermediates_expand_to_exact_tensor(self):
        dense, expected = naive_rectangular()
        for nested in [False, True]:
            data = circuit_version(dense, nested=nested)
            self.assertEqual(expected, self.convert(data)[1])
        # Repeated references are legitimate linear sums, not index aliases.
        data['u'][0].extend([dict(index=1, value=3), dict(index=1, value=-3)])
        self.assertEqual(expected, self.convert(data)[1])

    def test_malformed_circuits_are_rejected_without_writing(self):
        dense, _ = naive_rectangular()
        good = circuit_version(dense, nested=True)
        mutations = [
            lambda d: d['u_fresh'][0][0].update(index=4),  # self-reference
            lambda d: d['u_fresh'][0][0].update(index=5),  # forward reference
            lambda d: d['u_fresh'][0][0].update(index=-1),
            lambda d: d['v'][0][0].update(index=8),
            lambda d: d['w'][0][0].update(index=14),
            lambda d: d['w_fresh'][0][0].update(index=12),
            lambda d: d['u'][0][0].update(index=True),
            lambda d: d['u'][0][0].update(value=True),
            lambda d: d['u'][0][0].update(value=1.0),
            lambda d: d['v_fresh'][0][0].update(value='1/3'),
            lambda d: d['w'][0][0].update(extra=1),
            lambda d: d.update(u_fresh=None),
            lambda d: d.update(v_fresh={}),
            lambda d: d['w'].pop(),
            lambda d: d['u'].pop(),
            lambda d: d['u'].__setitem__(0, [1, 0, 0, 0]),
            lambda d: d.update(u_sparse={}),
            lambda d: d['w'][0][0].update(value=0),  # claimed tensor is false
        ]
        with tempfile.TemporaryDirectory(prefix='catalog-circuit-reject-') as root:
            source, output = Path(root) / 'source.json', Path(root) / 'output.txt'
            for index, mutate in enumerate(mutations):
                with self.subTest(index=index):
                    data = copy.deepcopy(good)
                    mutate(data)
                    source.write_text(json.dumps(data))
                    with self.assertRaises(ValueError):
                        importer.convert(source, output)
                    self.assertFalse(output.exists())

    def test_bad_sparse_encodings_are_rejected_without_writing(self):
        dense, _ = naive_rectangular()
        good = sparse_version(dense)
        mutations = [
            lambda d: d["u_sparse"].pop("0"),
            lambda d: d["u_sparse"].update({"12": {"i": [], "c": []}}),
            lambda d: d["u_sparse"]["0"].update(i=[0, 0], c=[1, 1]),
            lambda d: d["u_sparse"]["0"].update(i=[4]),
            lambda d: d["u_sparse"]["0"].update(i=[-1]),
            lambda d: d["u_sparse"]["0"].update(i=[True]),
            lambda d: d["u_sparse"]["0"].update(c=[]),
            lambda d: d["u_sparse"]["0"].update(c=["1/2"]),
            lambda d: d["u_sparse"]["0"].update(c=[1.0]),
            lambda d: d["u_sparse"]["0"].update(c=[True]),
            lambda d: d["u_sparse"]["0"].update(extra=1),
            lambda d: d.update(n=[0, 2, 3]),
            lambda d: d.update(n=[True, 2, 3]),
            lambda d: d.update(m=True),
            lambda d: d.update(fields=["Q"], fields_not=["F2"]),
            lambda d: d.update(fields_not=["F2"]),
            lambda d: d.update(verified=False),
            lambda d: d.update(commutative=True),
            lambda d: d.update(scheme_type='non_bilinear'),
        ]
        with tempfile.TemporaryDirectory(prefix="catalog-reject-") as root:
            source, output = Path(root) / "source.json", Path(root) / "output.txt"
            for index, mutate in enumerate(mutations):
                with self.subTest(index=index):
                    data = copy.deepcopy(good)
                    mutate(data)
                    source.write_text(json.dumps(data))
                    with self.assertRaises(ValueError):
                        importer.convert(source, output)
                    self.assertFalse(output.exists())

    def test_conflicting_encodings_and_false_tensor_claim_are_rejected(self):
        dense, _ = naive_rectangular()
        both = sparse_version(dense, keep_dense=True)
        both["u_sparse"]["0"]["c"] = [-1]
        with self.assertRaisesRegex(ValueError, "conflicting"):
            self.convert(both)
        corrupt = sparse_version(dense)
        corrupt["u_sparse"]["0"]["i"] = [1]
        with self.assertRaisesRegex(ValueError, "tensor mismatch"):
            self.convert(corrupt)


if __name__ == "__main__":
    unittest.main()
