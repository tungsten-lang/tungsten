#!/usr/bin/env python3
"""Native CLI regression for sparse DIMACS inputs beyond String's 2 GiB limit."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def main():
    binary = str(Path(sys.argv[1]).resolve())
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("WASSAT_", "TUNGSTEN_"))}
    env["WASSAT_BACKDOOR_TABLES"] = "0"
    with tempfile.TemporaryDirectory(prefix="wassat-large-parser-") as tmp:
        root = Path(tmp)
        source = root / "large.cnf"
        prefix = b"p cnf 1 1\nc "
        suffix = b"\n1 0\n"
        end = 2147483648 + 128
        with source.open("wb") as f:
            f.write(prefix)
            f.seek(end)
            f.write(suffix)
        proof = root / "out.drat"

        def run(path, args, code):
            p = subprocess.run([binary, str(path), *map(str, args)], env=env,
                               capture_output=True, text=True, timeout=30)
            assert p.returncode == code, (p.returncode, p.stdout, p.stderr)
            return p

        for args in (["--fast"], ["--drat", proof]):
            proof.write_text("stale certificate\n")
            p = run(source, args, 10)
            assert re.findall(r"^s (.+)$", p.stdout, re.M) == ["SATISFIABLE"]
            model = [int(x) for line in p.stdout.splitlines() if line.startswith("v ")
                     for x in line[2:].split() if x != "0"]
            # The sparse hole lies entirely in a DIMACS comment. The only
            # original clause is the unit 1, so this is a complete model check.
            assert model == [1], model
            if args[0] == "--drat":
                assert not proof.exists(), "SAT left a stale certificate"

        alias = root / "input-alias.drat"
        os.link(source, alias)
        p = run(source, ["--drat", alias], 1)
        assert "input" in p.stdout, p.stdout
        assert source.stat().st_size == end + len(suffix)
        with source.open("rb") as f:
            assert f.read(len(prefix)) == prefix
            f.seek(end)
            assert f.read() == suffix
        alias.unlink()

        # Malformed large input clears stale output, while an unreadable input
        # must fail before touching it. Neither may leave a temporary proof.
        with source.open("r+b") as f:
            f.seek(end)
            f.write(b"\n2 0\n")
        proof.write_text("stale certificate\n")
        p = run(source, ["--drat", proof], 1)
        assert "literal exceeds declared variable count" in p.stdout, p.stdout
        assert not proof.exists()
        proof.write_text("keep on missing input\n")
        p = run(root / "missing.cnf", ["--drat", proof], 1)
        assert "cannot read input formula" in p.stdout, p.stdout
        assert proof.read_text() == "keep on missing input\n"
        assert {p.name for p in root.iterdir()} == {source.name, proof.name}
    print("large input CLI: SAT/model, proof cleanup, alias and read-error checks passed")


if __name__ == "__main__":
    main()
