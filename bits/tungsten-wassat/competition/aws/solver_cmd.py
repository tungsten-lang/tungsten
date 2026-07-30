"""SAT Competition 2026 AWS shim for Wassat's parallel entrypoint."""

from pathlib import Path
from typing import List

from common.solver_io import SolverInput, SolverResultCode


# stage.sh installs the selected entrypoint as /wassat/run.sh. Keeping the
# harness pointed at that top-level contract also ensures it uses the binary
# produced by the staged top-level build.sh.
RUNNER = "/wassat/run.sh"


def get_run_command(s_input: SolverInput) -> List[str]:
    return [RUNNER, str(s_input.formula_file)]


def get_solver_result(stdout_path: Path) -> SolverResultCode:
    if not stdout_path.exists():
        return SolverResultCode.INDETERMINATE

    # Strict ASCII decoding is a deliberate guard: competition stdout must be
    # ASCII, so a non-ASCII or unreadable file classifies as INDETERMINATE.
    statuses = []
    try:
        with stdout_path.open("r", encoding="ascii", errors="strict") as output:
            for raw_line in output:
                line = raw_line.strip()
                if line in ("s SATISFIABLE", "s UNSATISFIABLE", "s UNKNOWN"):
                    statuses.append(line)
    except (UnicodeDecodeError, OSError):
        return SolverResultCode.INDETERMINATE

    if statuses == ["s SATISFIABLE"]:
        return SolverResultCode.SAT
    if statuses == ["s UNSATISFIABLE"]:
        return SolverResultCode.UNSAT
    if statuses == ["s UNKNOWN"]:
        return SolverResultCode.UNKNOWN
    return SolverResultCode.INDETERMINATE


def get_cleanup_command() -> List[str]:
    # Parallel jobs are one process with joined worker threads.
    return ["true"]
