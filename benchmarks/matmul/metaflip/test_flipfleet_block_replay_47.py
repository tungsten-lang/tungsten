#!/usr/bin/env python3
"""Focused exact replay gate for the explicit rank-47 block CLI."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path(__file__).with_name('flipfleet_block_replay_47.w')
SEEDS = ROOT / 'bits/tungsten-metaflip/lib/metaflip/seeds/gf2'
VERIFIER = ROOT / 'bits/tungsten-metaflip/tools/verify_tensor.rb'


class BlockReplay47Test(unittest.TestCase):
    def test_exact_composition_and_bad_leaf_rejection(self):
        with tempfile.TemporaryDirectory(prefix='metaflip-block-replay-') as directory:
            temp = Path(directory)
            binary = temp / 'replay-47'
            subprocess.run([str(ROOT / 'bin/tungsten'), 'compile', str(SOURCE),
                            '--release', '--native', '--no-lto', '--out', str(binary)],
                           cwd=ROOT, check=True, capture_output=True, text=True)
            outer = SEEDS / 'matmul_4x4_rank47_d450_gf2.txt'
            leaf346 = SEEDS / 'matmul_3x4x6_rank54_d488_gl_frontier_gf2.txt'
            leaf446 = SEEDS / 'matmul_4x4x6_rank73_d690_gl_frontier_gf2.txt'
            output = temp / '14x16x24.txt'
            args = [str(binary), '3,4,4,3', '4,4,4,4', '6,6,6,6',
                    str(outer), str(output), '3', '4', '6', str(leaf346),
                    '4', '4', '6', str(leaf446)]
            replay = subprocess.run(args, cwd=ROOT, check=True,
                                    capture_output=True, text=True)
            self.assertIn('exact rank 3089', replay.stdout)
            checked = json.loads(subprocess.check_output(
                ['ruby', str(VERIFIER), '--shape', '14x16x24', str(output)],
                cwd=ROOT, text=True))[0]
            self.assertTrue(checked['exact'])
            self.assertEqual(checked['rank'], 3089)

            bad_output = temp / 'bad.txt'
            bad_args = args.copy()
            bad_args[5] = str(bad_output)
            bad_args[-2] = '5'
            rejected = subprocess.run(bad_args, cwd=ROOT,
                                      capture_output=True, text=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertFalse(bad_output.exists())


if __name__ == '__main__':
    unittest.main()
