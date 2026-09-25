#!/usr/bin/env python3
"""Exact native/Python parity for all three multiword pair-composition axes."""
import base64
import gzip
from pathlib import Path
import subprocess
import sys
import tempfile

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import screen_top_two_projection_children as tensor  # noqa: E402
from wide_pair_composition import compose_pairs  # noqa: E402


def control():
    certificate = (TOOLS / "certificates/7x12x16-r871-directed-20260925/"
                   "7x16x12-r871-mode7.mfw.gz.b64")
    raw = gzip.decompress(base64.b64decode(certificate.read_bytes()))
    shape, terms = tensor.read_blob(raw)
    tensor.exact(shape, terms)
    while shape[1] > 10:
        shape, terms = tensor.project(shape, terms, 1, shape[1] - 1)
    while shape[2] > 7:
        shape, terms = tensor.project(shape, terms, 2, shape[2] - 1)
    terms, _ = tensor.compress_shared(terms, max_bits=1024)
    assert shape == (7, 10, 7) and len(terms) <= 2000
    assert max(shape[0] * shape[1], shape[1] * shape[2]) > 64
    tensor.exact(shape, terms)
    return shape, terms


def check(binary):
    shape, terms = control()
    with tempfile.TemporaryDirectory(prefix="metaflip-native-wide-pair-") as temp:
        root = Path(temp)
        source = root / "source.mfw"
        source.write_bytes(tensor.blob(shape, terms))
        shape, terms = tensor.read_blob(source.read_bytes())
        for axis in range(3):
            output = root / f"axis-{axis}.mfw"
            process = subprocess.run([str(Path(binary).resolve()), str(source),
                                      str(output), str(axis)], capture_output=True,
                                     text=True, timeout=45)
            assert process.returncode == 0, (axis, process.stdout, process.stderr)
            expected = compose_pairs(shape, terms, axis)
            assert expected is not None
            exact = tensor.blob(expected[0], expected[1])
            assert output.read_bytes() == exact, (axis, process.stdout)
            tensor.exact(*tensor.read_blob(output.read_bytes()))
            print(f"PASS axis {axis}: {shape} r{len(terms)} -> "
                  f"{expected[0]} r{len(expected[1])}, pairs {expected[2]}")


if __name__ == "__main__":
    check(sys.argv[1])
