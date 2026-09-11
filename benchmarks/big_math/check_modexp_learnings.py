#!/usr/bin/env python3
"""Check MODEXP-derived runtime changes against Python's independent pow.

Usage: python3 benchmarks/big_math/check_modexp_learnings.py --out build/modexp-oracle
The output directory must be new; retain the fixture, vectors and build/run logs.
"""

import argparse
import hashlib
import json
import random
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PRIMES = {
    "bn254": 21888242871839275222246405745257275088696311157297823662689037894645226208583,
    "secp256k1": 2**256 - 2**32 - 977,
}


def vectors():
    rng = random.Random(8200)
    rows = []

    def add(name, base, exponent, modulus):
        rows.append(dict(name=name, base=str(base), exponent=str(exponent),
                         modulus=str(modulus), want=str(pow(base, exponent, abs(modulus)))))

    for name, p in PRIMES.items():
        for i in range(24):
            b = rng.getrandbits(32 * (i + 1))
            if i % 3 == 0:
                b *= p
            add(f"{name}.signed.{i}", -b if i % 2 else b, p - 1,
                -p if i % 4 < 2 else p)
        for bit in (0, 63, 64, 127, 128, 191, 192, 255, 256):
            add(f"{name}.exponent_bit.{bit}", 7, (p - 1) ^ (1 << bit), p)
            m = p ^ (1 << bit)
            add(f"{name}.modulus_bit.{bit}", 7, m - 1, m)

    # Register, raw Montgomery, truncated REDC and Barrett admission boundaries.
    # Even moduli and signed/oversized bases must retain their general behavior.
    for k in (1, 2, 3, 4, 8, 16, 32, 47, 48, 49, 96, 97):
        for odd in (0, 1):
            m = (1 << (64 * k - 1)) | (rng.getrandbits(64 * k - 1) & ~1) | odd
            b = rng.getrandbits(64 * k + 19)
            for e in (3, 65537):
                add(f"width.{k}.odd.{odd}.e.{e}", -b if odd else b, e,
                    -m if e == 3 else m)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    rows = vectors()
    (out / "vectors.json").write_text(json.dumps(rows, indent=2) + "\n")
    fixture = out / "oracle.w"
    source = '''-> check_case(name, b, e, m, want)
  before_b = b.to_s()
  before_e = e.to_s()
  before_m = m.to_s()
  got = b.modpow(e, m).to_s()
  if got != want || b.to_s() != before_b || e.to_s() != before_e || m.to_s() != before_m
    << "FAIL " + name + " got " + got + " want " + want
    exit 1
  << "PASS " + name

'''
    for r in rows:
        source += (f'check_case("{r["name"]}", {r["base"]}, {r["exponent"]}, '
                   f'{r["modulus"]}, "{r["want"]}")\n')
    fixture.write_text(source)
    commands = []
    for lane, flags in (("debug", ["--no-lto"]), ("release", ["--release", "--native", "--fast"])):
        binary = out / lane
        command = [str(ROOT / "bin/tungsten"), "compile", str(fixture), *flags, "--out", str(binary)]
        commands.append(command)
        with (out / f"{lane}-build.log").open("w") as log:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        with (out / f"{lane}-run.log").open("w") as log:
            subprocess.run([str(binary)], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        lines = (out / f"{lane}-run.log").read_text().splitlines()
        assert lines == ["PASS " + r["name"] for r in rows], lane
        print(f"{lane}: {len(rows)} independent pow results and operand-preservation checks PASS", flush=True)
    summary = dict(cases=len(rows), seed=8200, lanes=["debug", "release"],
                   fixture_sha256=hashlib.sha256(fixture.read_bytes()).hexdigest(),
                   runtime_sha256=hashlib.sha256((ROOT / "runtime/runtime.c").read_bytes()).hexdigest(),
                   commands=commands, result="PASS")
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
