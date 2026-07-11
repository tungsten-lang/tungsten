import random
import tempfile
import unittest

from metaflip_proto2 import T, naive, recon
from sym_escape import (
    best_bridge,
    bridge_error,
    c3_image,
    c3_orbit,
    cube,
    describe,
    fixed_terms,
    emit_bare,
    emit_scheme,
    is_c3_closed,
    load_scheme,
    orbit_split_identity,
    parity_terms,
    polarization_identity,
    split_identity,
    main as sym_escape_main,
    toggle_identity,
    transpose,
)


def _bits(mask):
    while mask:
        low = mask & -mask
        yield low.bit_length() - 1
        mask ^= low


def _rank_one_tensor(term, dimension):
    """Compact exact tensor signature used by the exhaustive identity tests."""
    u, v, w = term
    vw = 0
    for b in _bits(v):
        vw ^= w << (b * dimension)
    out = 0
    for a in _bits(u):
        out ^= vw << (a * dimension * dimension)
    return out


def _tensor_signature(terms, dimension):
    out = 0
    for term in parity_terms(terms):
        out ^= _rank_one_tensor(term, dimension)
    return out


class SymmetryEscapeTests(unittest.TestCase):
    def test_c3_action_has_order_three(self):
        rng = random.Random(78123)
        for _ in range(1000):
            term = tuple(rng.randrange(1, 512) for _ in range(3))
            orbit = c3_orbit(term, 3)
            self.assertIn(term, orbit)
            self.assertIn(len(orbit), (1, 3))
            self.assertEqual(c3_image(c3_image(c3_image(term, 3), 3), 3), term)

    def test_all_n3_fixed_splits_are_tensor_zero(self):
        dimension = 9
        for x in range(1, 1 << dimension):
            term = cube(x, 3)
            for part in range(1, 1 << dimension):
                if part == x:
                    continue
                for axis in range(3):
                    axis_part = transpose(part, 3) if axis == 2 else part
                    self.assertEqual(
                        _tensor_signature(
                            split_identity(term, axis, axis_part), dimension
                        ),
                        0,
                    )

    def test_all_n3_orbit_splits_are_tensor_zero_and_c3_closed(self):
        dimension = 9
        for x in range(1, 1 << dimension):
            for part in range(1, 1 << dimension):
                if part == x:
                    continue
                identity = orbit_split_identity(x, part, 3)
                self.assertTrue(is_c3_closed(identity, 3))
                self.assertEqual(_tensor_signature(identity, dimension), 0)

    def test_all_n3_polarizations_are_tensor_zero_and_c3_closed(self):
        dimension = 9
        for x in range(1, 1 << dimension):
            for y in range(x + 1, 1 << dimension):
                identity = polarization_identity(x, y, 3)
                self.assertTrue(is_c3_closed(identity, 3))
                self.assertEqual(_tensor_signature(identity, dimension), 0)

    def test_random_sequences_preserve_an_exact_n3_scheme(self):
        rng = random.Random(227091)
        scheme = naive(3, 3, 3)
        for _ in range(200):
            fixed = rng.choice(fixed_terms(scheme, 3))
            x = fixed[0]
            part = rng.randrange(1, 512)
            while part == x:
                part = rng.randrange(1, 512)
            scheme = toggle_identity(scheme, orbit_split_identity(x, part, 3))
            self.assertTrue(is_c3_closed(scheme, 3))
            self.assertEqual(recon(scheme, 3, 3, 3), T(3, 3, 3))
            # The same involution restores the exact prior scheme, keeping this
            # randomized test bounded while exercising collision cancellation.
            scheme = toggle_identity(scheme, orbit_split_identity(x, part, 3))
        self.assertEqual(scheme, naive(3, 3, 3))

    def test_best_bridge_breaks_or_preserves_symmetry_as_requested(self):
        scheme = naive(3, 3, 3)
        broken, _ = best_bridge(scheme, 3, kind="break")
        symmetric, _ = best_bridge(scheme, 3, kind="orbit-split")
        polarized, _ = best_bridge(scheme, 3, kind="polarize")
        for output in (broken, symmetric, polarized):
            self.assertEqual(recon(output, 3, 3, 3), T(3, 3, 3))
        self.assertFalse(is_c3_closed(broken, 3))
        self.assertTrue(is_c3_closed(symmetric, 3))
        self.assertTrue(is_c3_closed(polarized, 3))

    def test_generic_split_works_without_a_fixed_cube(self):
        # Deliberately break every fixed cube while keeping an exact scheme.
        scheme = naive(3, 3, 3)
        for term in list(fixed_terms(scheme, 3)):
            scheme = toggle_identity(scheme, split_identity(term, 0, 2))
        self.assertFalse(fixed_terms(scheme, 3))
        self.assertIsNone(bridge_error(scheme, 3, "split"))
        self.assertIn("fixed C3", bridge_error(scheme, 3, "break"))
        output, metadata = best_bridge(scheme, 3, kind="split")
        self.assertEqual("split", metadata["kind"])
        self.assertEqual(recon(output, 3, 3, 3), T(3, 3, 3))
        self.assertEqual(output, best_bridge(list(reversed(sorted(scheme))), 3,
                                             kind="split")[0])

    def test_transpose_is_an_involution(self):
        for mask in range(512):
            self.assertEqual(transpose(transpose(mask, 3), 3), mask)

    def test_bare_output_round_trips(self):
        scheme = naive(3, 3, 3)
        with tempfile.NamedTemporaryFile(mode="w+", suffix=".txt") as stream:
            emit_bare(scheme, stream)
            stream.flush()
            self.assertEqual(load_scheme(stream.name, 3), scheme)

    def test_all_output_styles_round_trip(self):
        scheme = naive(3, 3, 3)
        for style in ("bare", "r", "usvw"):
            with self.subTest(style=style):
                with tempfile.NamedTemporaryFile(mode="w+", suffix=".txt") as stream:
                    emit_scheme(scheme, stream, style)
                    stream.flush()
                    self.assertEqual(load_scheme(stream.name, 3), scheme)

    def test_exact_gate_rejects_out_of_range_masks(self):
        scheme = set(naive(3, 3, 3))
        term = next(iter(scheme))
        scheme.remove(term)
        scheme.add((term[0] | (1 << 40), term[1], term[2]))
        info = describe(scheme, 3)
        self.assertFalse(info["well_formed"])
        self.assertFalse(info["exact"])
        with self.assertRaises(ValueError):
            describe(scheme, 0)

    def test_c3_bridge_rejects_non_c3_input(self):
        scheme = naive(3, 3, 3)
        term = fixed_terms(scheme, 3)[0]
        broken = toggle_identity(scheme, split_identity(term, 0, 2))
        self.assertFalse(is_c3_closed(broken, 3))
        with tempfile.NamedTemporaryFile(mode="w+", suffix=".txt") as stream:
            emit_bare(broken, stream)
            stream.flush()
            with self.assertRaisesRegex(SystemExit, "requires a C3-closed"):
                sym_escape_main(["bridge", stream.name, "3", "--kind", "orbit-split"])


if __name__ == "__main__":
    unittest.main()
