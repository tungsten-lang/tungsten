import hashlib
from itertools import permutations, product
import json
from pathlib import Path
import tempfile
import unittest

from structured_exp_import import checked_projection, import_file, parse_integer_exp


def naive_exp(shape):
    n, m, p = shape
    return ''.join(f'(a{i+1}{j+1})*(b{j+1}{k+1})*(c{k+1}{i+1})\n'
                   for i, j, k in product(range(n), range(m), range(p))).encode()


def naive_terms(shape):
    n, m, p = shape
    return sorted((1 << (i*m+j), 1 << (j*p+k), 1 << (i*p+k))
                  for i, j, k in product(range(n), range(m), range(p)))


class StructuredExpImportTest(unittest.TestCase):
    def test_all_rectangular_source_and_target_orientations(self):
        for source in permutations((2, 3, 4)):
            for target in permutations((2, 3, 4)):
                with self.subTest(source=source, target=target):
                    result = checked_projection(naive_exp(source), target)
                    self.assertEqual(result['source_shape'], list(source))
                    self.assertEqual(result['terms'], naive_terms(target))
                    self.assertEqual(result['verification']['exact_rank'], 24)

    def test_integer_coefficients_zero_mod_two_and_parity_cancellation(self):
        raw = naive_exp((2, 3, 4)) + b'\n'.join([
            b'(2a11)*(b11-b12)*(c11)',
            b'(-2*a11)*(b11-b12)*(c11)',
            b'(a11)*(b11)*(c11)',
            b'(-a11)*(b11)*(c11)',
        ])
        result = checked_projection(raw, (2, 3, 4))
        self.assertEqual(result['integer_terms'], 28)
        self.assertEqual(result['rank'], 24)
        self.assertEqual(result['terms'], naive_terms((2, 3, 4)))

    def test_repeated_coordinates_and_explicit_positive_sign(self):
        forms = parse_integer_exp(b'( a11+a11-a11 ) * ( +b11 ) * ( c11 )\n')
        self.assertEqual(forms, [({(0, 0): 1}, {(0, 0): 1}, {(0, 0): 1})])
        self.assertEqual(checked_projection(b'(a11)*(b11)*(c11)', (1, 1, 1))['rank'], 1)

    def test_valid_mod_two_but_invalid_integer_tensor_is_rejected(self):
        raw = naive_exp((2, 3, 4)) + b'(2a11)*(b11)*(c11)\n'
        with self.assertRaisesRegex(ValueError, 'integer tensor mismatch'):
            checked_projection(raw, (2, 3, 4))

    def test_missing_term_wrong_orientation_and_shape_are_rejected(self):
        raw = naive_exp((2, 3, 4))
        with self.assertRaisesRegex(ValueError, 'integer tensor mismatch'):
            checked_projection(b'\n'.join(raw.splitlines()[1:]), (2, 3, 4))
        with self.assertRaisesRegex(ValueError, 'not a permutation'):
            checked_projection(raw, (2, 3, 5))
        wrong = raw.replace(b'c41', b'c14').replace(b'c42', b'c24')
        with self.assertRaisesRegex(ValueError, 'trace-coordinate'):
            checked_projection(wrong, (2, 3, 4))
        for shape in ((2, 3), (0, 3, 4), (2, 3, 10), (True, 3, 4)):
            with self.subTest(shape=shape), self.assertRaises(ValueError):
                checked_projection(raw, shape)

    def test_reject_unparsed_syntax_and_zero_forms(self):
        for form in ('a11a12', 'a11**2', 'a11/2', 'a11+2', 'a00', 'a101',
                     'a11-a11', '0a11', 'b11', '__import__("os")', 'a11+-a12'):
            with self.subTest(form=form), self.assertRaises(ValueError):
                parse_integer_exp(f'({form})*(b11)*(c11)'.encode())
        for raw in (b'', b'(a11)*(b11)', b'(a11)*(b11)*(c11);print(1)'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                parse_integer_exp(raw)

    def test_file_import_hashes_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            source, output = root/'234.exp', root/'import'
            raw = naive_exp((4, 2, 3))
            source.write_bytes(raw)
            digest = hashlib.sha256(raw).hexdigest()
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                import_file(source, (2, 3, 4), '0'*64, output)
            self.assertFalse(output.exists())
            with self.assertRaisesRegex(ValueError, 'not a permutation'):
                import_file(source, (2, 3, 5), digest, output)
            self.assertFalse(output.exists())
            report = import_file(source, (2, 3, 4), digest, output)
            self.assertEqual(json.loads((output/'report.json').read_text()), report)
            self.assertEqual((output/'source.exp').read_bytes(), raw)
            self.assertEqual(hashlib.sha256((output/'tensor.txt').read_bytes()).hexdigest(), report['sha256'])
            self.assertEqual(report['source_shape'], [4, 2, 3])
            self.assertTrue(report['imported_not_discovered'])
            self.assertFalse(report['record_claim'] or report['canonical_archive_changed'] or report['redistribution_cleared'])
            with self.assertRaisesRegex(ValueError, 'must not exist'):
                import_file(source, (2, 3, 4), digest, output)


if __name__ == '__main__':
    unittest.main()
