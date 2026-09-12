#!/usr/bin/env python3
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from recover_wide_local_seeds import normalize, publish_new


class RecoveryTest(unittest.TestCase):
    def test_exact_conversion_and_corruption(self):
        raw = b'R 1 1 1\n'
        digest = hashlib.sha256(raw).hexdigest()
        self.assertEqual(normalize(raw, 1, 1, digest), b'MFW1 1 1 1 1\n1 1 1\n')
        for data, rank, sha in ((raw, 1, 'bad'), (raw, 2, digest),
                                (b'R 1 1 2\n', 1, hashlib.sha256(b'R 1 1 2\n').hexdigest())):
            with self.assertRaises(ValueError):
                normalize(data, 1, rank, sha)

    def test_no_clobber_even_if_existing_is_invalid(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)/'shape/best.txt'
            self.assertTrue(publish_new(target, b'existing user bytes'))
            self.assertFalse(publish_new(target, b'new exact witness'))
            self.assertEqual(target.read_bytes(), b'existing user bytes')
            self.assertEqual(list(target.parent.iterdir()), [target])


if __name__ == '__main__':
    unittest.main()
