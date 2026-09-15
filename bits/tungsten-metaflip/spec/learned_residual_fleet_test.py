#!/usr/bin/env python3
"""Unqualified research must not leave a hidden or opt-in production arm."""
from pathlib import Path
import subprocess
import sys
import tempfile

from refinement_fleet_test import run

ROOT = Path(__file__).resolve().parents[1]


def main():
    binary = Path(sys.argv[1]).resolve()
    runtime = ROOT / "lib/metaflip"
    for source in runtime.rglob("*.w"):
        body = source.read_text()
        assert "fflr_" not in body, source
        assert "--learned-residual" not in body, source
        assert "learned_model" not in body, source
    assert not list(runtime.rglob("*.mfl")), "research model leaked into runtime assets"
    for manifest in (runtime / "SHA256SUMS", runtime / "manifests/runtime-sources.tsv"):
        assert "learned_residual" not in manifest.read_text()
        assert "residual-v1.mfl" not in manifest.read_text()
    help_run = subprocess.run([str(binary), "--help"], capture_output=True, text=True, timeout=8)
    assert help_run.returncode == 0 and "--learned-residual" not in help_run.stdout
    rejected = subprocess.run([str(binary), "--tensor", "5x5", "--learned-residual", "unused"],
                              capture_output=True, text=True, timeout=8)
    assert rejected.returncode == 2
    with tempfile.TemporaryDirectory(prefix="metaflip-automatic-refinement-") as temporary:
        for shape in ("2x2", "2x4x5"):
            root = Path(temporary) / shape
            run(binary, root, shape, 1, seconds=2)
            assert "learned_" not in (root / "status.txt").read_text()
            assert not list(root.glob("status.txt.refinement-lr*"))
            assert not list(root.rglob("learned-model"))
    print("PASS no learned flag, hidden fallback, model asset or production hook; automatic refinement unchanged")


if __name__ == "__main__":
    main()
