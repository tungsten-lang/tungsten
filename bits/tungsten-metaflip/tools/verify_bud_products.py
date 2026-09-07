#!/usr/bin/env python3
"""Audit bud outputs with the repository's older, independent Python verifier.

The adapter only changes the text container (rank header -> R-prefixed rows).
It imports no bud composer or Ruby verifier. Supply the existing verifier
explicitly so a standalone bit installation has no hidden repo dependency.
"""
import argparse
import dataclasses
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verifier", required=True, type=Path)
    parser.add_argument("recipes", nargs="+", type=Path)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("independent_block_verifier", args.verifier)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    results = []
    with tempfile.TemporaryDirectory(prefix="metaflip-bud-independent-") as temporary:
        output = Path(temporary)
        for index, path in enumerate(args.recipes):
            recipe = json.loads(path.read_text())
            if type(recipe.get("schema")) is not int or recipe["schema"] not in (1, 2) or recipe.get("field") != "GF(2)":
                raise ValueError(f"{path}: unsupported recipe")
            entry = recipe["result"]
            root = path.resolve().parent
            certificate = (root / entry["path"]).resolve()
            if not certificate.is_relative_to(root):
                raise ValueError(f"{path}: certificate outside recipe directory")
            raw = certificate.read_bytes()
            digest = hashlib.sha256(raw).hexdigest()
            if digest != entry["sha256"]:
                raise ValueError(f"{path}: certificate hash mismatch")
            lines = raw.decode("ascii").splitlines()
            if not lines or int(lines[0]) != recipe["exact_rank"] or len(lines) - 1 != recipe["exact_rank"]:
                raise ValueError(f"{path}: inconsistent rank header")
            converted = "".join("R " + line + "\n" for line in lines[1:]).encode("ascii")
            adapted = output / f"{index}.txt"
            adapted.write_bytes(converted)
            shape = tuple(entry["shape"])
            if len(shape) != 3 or any(type(d) is not int or d <= 0 for d in shape):
                raise ValueError(f"{path}: invalid dimensions")
            record = module.Record("x".join(map(str, shape)), shape, recipe["exact_rank"], adapted.name,
                                   hashlib.sha256(converted).hexdigest())
            verified = module._verify_one((output, record))
            result = dataclasses.asdict(verified)
            result.pop("certificate")  # temporary adapter path is not a proof artifact
            result["adapted_sha256"] = result.pop("sha256")
            result.update(recipe=str(path.resolve()), certificate=str(certificate), sha256=digest)
            results.append(result)
    print(json.dumps(dict(python=platform.python_version(), verifier=str(args.verifier.resolve()),
                          verifier_sha256=hashlib.sha256(args.verifier.read_bytes()).hexdigest(),
                          cases=len(results), terms=sum(r["terms"] for r in results),
                          pair_xors=sum(r["pair_xors"] for r in results), results=results), indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Independent bud audit failed: {error}", file=sys.stderr)
        sys.exit(1)
