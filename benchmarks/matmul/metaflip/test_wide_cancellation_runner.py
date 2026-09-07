"""Focused tests for the optional, standalone wide-factor experiment."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


def naive(n, m, p):
    return [(1 << (i * m + j), 1 << (j * p + k), 1 << (i * p + k))
            for i in range(n) for j in range(m) for k in range(p)]


def bits(value):
    while value:
        low = value & -value
        yield low.bit_length() - 1
        value ^= low


def exact(terms, shape):
    n, m, p = shape
    values = [0] * (n * m * m * p)
    for u, v, w in terms:
        assert 0 < u < 1 << (n * m) and 0 < v < 1 << (m * p) and 0 < w < 1 << (n * p)
        for i in bits(u):
            for j in bits(v):
                values[i * m * p + j] ^= w
    for i in range(n):
        for j in range(m):
            for k in range(p):
                values[(i * m + j) * m * p + j * p + k] ^= 1 << (i * p + k)
    assert not any(values)


class WideCancellationRunnerTest(unittest.TestCase):
    def setUp(self):
        value = os.environ.get('METAFLIP_WIDE_BINARY')
        if not value:
            self.skipTest('set METAFLIP_WIDE_BINARY to the built experimental tool')
        self.binary = Path(value).resolve()
        self.assertTrue(self.binary.is_file())
        self.tmp = tempfile.TemporaryDirectory(prefix='metaflip-wide-runner-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('WIDE_')}

    def seed(self, name, terms):
        path = self.root / name
        path.write_text(str(len(terms)) + '\n' + ''.join(' '.join(map(str, t)) + '\n' for t in terms))
        return path

    def run_case(self, source, shape, name, steps=10000, debt=2, sampler='eligible', environment=None):
        command = [str(self.binary), str(source), *map(str, shape), str(steps), '1', str(debt), '4317', str(self.root / name), sampler]
        return subprocess.run(command, capture_output=True, text=True, timeout=60,
                              env=self.env | (environment or {}))

    def terms(self, folder, name):
        lines = (self.root / folder / name).read_text().splitlines()
        self.assertEqual(int(lines[0]), len(lines) - 1)
        return [tuple(map(int, line.split())) for line in lines[1:]]

    def test_exact_reproducible_walk_and_checkpoint(self):
        source = self.seed('seed.txt', naive(2, 2, 2))
        outputs = []
        for name in ('first', 'second'):
            result = self.run_case(source, (2, 2, 2), name, environment={'WIDE_COMPRESS_EVERY': '17'})
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(result.stdout)
            for key in ('result', 'final'):
                exact(self.terms(name, data[key]), (2, 2, 2))
            data.pop('seconds')
            outputs.append(data)
        self.assertEqual(outputs[0], outputs[1])
        for name in ('trial-0.txt', 'trial-0-final.txt'):
            self.assertEqual((self.root / 'first' / name).read_bytes(), (self.root / 'second' / name).read_bytes())
        again = self.run_case(source, (2, 2, 2), 'first')
        self.assertEqual(again.returncode, 2)

    def test_rejects_corrupt_tensor_width_and_invalid_search_limits(self):
        original = naive(2, 2, 2)
        bad = original.copy(); bad[0] = (bad[0][0], bad[0][1], 2)
        variants = [('tensor', self.seed('bad-tensor.txt', bad), (2, 2, 2), 100, 2),
                    ('shape', self.seed('valid.txt', original), (0, 2, 2), 100, 2),
                    ('steps', self.root / 'valid.txt', (2, 2, 2), 0, 2),
                    ('debt', self.root / 'valid.txt', (2, 2, 2), 100, 9)]
        wider = original.copy(); wider[0] = (1 << 256, 1, 1)
        variants.append(('width', self.seed('bad-width.txt', wider), (2, 2, 2), 100, 2))
        for name, source, shape, steps, debt in variants:
            result = self.run_case(source, shape, name, steps, debt)
            self.assertEqual(result.returncode, 2, (name, result.stdout, result.stderr))
            self.assertFalse((self.root / name).exists())

    def test_highest_supported_coefficient_bit(self):
        shape = (16, 16, 16)
        source = self.seed('wide.txt', naive(*shape))
        result = self.run_case(source, shape, 'wide', steps=1, debt=0)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        exact(self.terms('wide', data['result']), shape)
        exact(self.terms('wide', data['final']), shape)


if __name__ == '__main__':
    unittest.main()
