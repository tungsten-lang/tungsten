"""Replay clean CNF deadline refutations and the guarded clauses on the original."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cake", type=Path, required=True)
parser.add_argument("--cake-lpr", type=Path, required=True)
args = parser.parse_args()
directory = Path(__file__).resolve().parent
original = directory / "input.cnf"
data = original.read_bytes()
assert hashlib.sha256(data).hexdigest() == "6d6a406144bf3d3e20efa43e79395612596ac413efba1fac5b59f190c43cff79"
base = data.splitlines()[1:]
env = os.environ | {"CML_HEAP_SIZE": "1500", "CML_STACK_SIZE": "128"}
with tempfile.TemporaryDirectory() as td:
    tmp = Path(td)
    for spec in (directory / "deadlines.txt").read_text().splitlines():
        name, *xs = spec.split()
        units = list(map(int, xs))
        assert units[:8] == [4167,4171,4175,4199,2,29,58,4184] and (len(units)==9 or (len(units)==10 and units[8]==4187))
        clauses = base + [f"{lit} 0".encode() for lit in units]
        child = tmp / "child.cnf"
        child.write_bytes(f"p cnf 18420 {len(clauses)}\n".encode() + b"\n".join(clauses) + b"\n")
        proof = directory / (name + ".lpr.zst")
        with subprocess.Popen(["zstd","-qdc",proof],stdout=subprocess.PIPE) as z:
            checked=subprocess.run([args.cake_lpr.resolve(),child,"/dev/stdin"],stdin=z.stdout,capture_output=True,env=env)
            z.stdout.close()
            if z.wait() or checked.returncode or checked.stdout.strip()!=b"s VERIFIED UNSAT":
                raise RuntimeError((name,checked.stdout,checked.stderr))
        print(name, "s VERIFIED UNSAT", flush=True)
        translator = tmp / "lift"
        if not translator.exists():
            subprocess.run([os.environ.get("CXX","c++"),"-std=c++17","-O2",directory/"stapleguard.cpp","-o",translator],check=True)
        mapping = tmp / "assumptions"
        mapping.write_text(" ".join("0" for _ in units))
        with subprocess.Popen([args.cake.resolve(),original,"/dev/stdin"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,env=env) as cake:
            cake.stdin.write(b"pseudo-Boolean proof version 3.0\nf 83276;\n")
            cake.stdin.flush()
            with subprocess.Popen(["zstd","-qdc",proof],stdout=subprocess.PIPE) as z:
                lift=subprocess.run([translator,mapping,"83276",*map(str,units)],stdin=z.stdout,stdout=cake.stdin,stderr=subprocess.PIPE)
                z.stdout.close()
                if z.wait() or lift.returncode:raise RuntimeError((name,lift.stderr))
            terms=" ".join("1 "+("~" if v>0 else "")+"x"+str(abs(v)) for v in units)
            last=int(lift.stderr)
            cake.stdin.write(f"rup {terms} >= 1 : ~ {last};\noutput NONE;\nconclusion NONE;\nend pseudo-Boolean proof;\n".encode())
            cake.stdin.close()
            result=cake.stdout.read().strip()
            if cake.wait() or result!=b"s VERIFIED NO CONCLUSION":raise RuntimeError((name,result))
            print(name,result.decode(),flush=True)
