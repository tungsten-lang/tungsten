"""Verify the union of excluded tail2 mode combinations on the original input."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cake-lpr", required=True, type=Path)
args = parser.parse_args()
directory = Path(__file__).resolve().parent
original = (directory / "input.cnf").read_bytes()
if hashlib.sha256(original).hexdigest() != "6d6a406144bf3d3e20efa43e79395612596ac413efba1fac5b59f190c43cff79":
    raise ValueError("unexpected competition input")
clauses = original.splitlines()[1:]
for literal in (4167, 4171, 4175, 4199):
    clauses.append(f"{literal} 0".encode())
cuts = (directory / "global-tail2-batch.modecuts").read_text().splitlines()
selectors = range(18421, 18421 + len(cuts))
clauses.append((" ".join(map(str, selectors)) + " 0").encode())
for selector, row in zip(selectors, cuts):
    literals = list(map(int, row.split()))
    if len(literals) < 2 or literals[-1] != 0 or any(v < -4256 or v > -4167 for v in literals[:-1]):
        raise ValueError("invalid mode condition")
    clauses.extend(f"{-selector} {-v} 0".encode() for v in literals[:-1])
with tempfile.TemporaryDirectory() as tmp:
    query = Path(tmp) / "query.cnf"
    header = f"p cnf {selectors[-1]} {len(clauses)}\n".encode()
    query.write_bytes(header + b"\n".join(clauses) + b"\n")
    with subprocess.Popen(["zstd", "-qdc", directory / "global-tail2-batch.lpr.zst"], stdout=subprocess.PIPE) as proof:
        checked = subprocess.run([args.cake_lpr.resolve(), query, "/dev/stdin"], stdin=proof.stdout, capture_output=True,
                                 env=os.environ | {"CML_HEAP_SIZE": "1500", "CML_STACK_SIZE": "128"})
        proof.stdout.close()
        if proof.wait() or checked.returncode or checked.stdout.strip() != b"s VERIFIED UNSAT":
            raise RuntimeError((checked.stdout, checked.stderr))
    print(f"VERIFIED UNSAT for union of {len(cuts)} tail2 mode conditions")
