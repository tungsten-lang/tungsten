"""q2draft was measured and deleted. This drives the remaining shipped selector."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
RUNNER = REPO / "scripts" / "bench" / "qwen38_mlx.w"
Q2_KERNEL = (
    REPO
    / "bits"
    / "tungsten-llama"
    / "lib"
    / "kernels"
    / "qwen3_6"
    / "mtp_draft_q2.metal"
)
SELECTOR = (
    REPO
    / "bits"
    / "tungsten-llama"
    / "lib"
    / "kernels"
    / "qwen3_6"
    / "mtp_draft_select_fast.metal"
)
SELECT_TEST = REPO / "bits" / "tungsten-llama" / "mtp_draft_select_test.w"
TUNGSTEN = REPO / "bin" / "tungsten"


def test_q2_kernel_file_is_gone() -> None:
    assert not Q2_KERNEL.exists(), f"rejected experiment still on disk: {Q2_KERNEL}"


def test_runner_does_not_compile_q2() -> None:
    src = RUNNER.read_text()
    assert "q2draft" not in src
    assert "mtp_draft_q2" not in src
    assert "mtp_draft_select_fast.metal" in src
    assert SELECTOR.is_file()


def test_shipped_tiled_selector_kernel() -> None:
    proc = subprocess.run(
        [str(TUNGSTEN), "run", str(SELECT_TEST.relative_to(REPO))],
        cwd=REPO,
        check=False,
        capture_output=True,
        text=True,
    )
    out = proc.stdout + proc.stderr
    sys.stdout.write(out)
    assert proc.returncode == 0, out
    assert "mtp_draft_select_fast shipped path PASS" in out
    assert "prefix winner PASS" in out
    assert "control winner PASS" in out
    assert "tie-break PASS" in out


if __name__ == "__main__":
    test_q2_kernel_file_is_gone()
    test_runner_does_not_compile_q2()
    test_shipped_tiled_selector_kernel()
    print("test_q2draft_removed PASS")
