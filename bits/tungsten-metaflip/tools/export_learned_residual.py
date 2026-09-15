#!/usr/bin/env python3
"""Export the local audited MLP to the bounded native MFLR1 interchange format.

No NumPy/runtime Python dependency. Input models contain data, never code.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path


def export(data):
    features = [f"mode_{a}_{f}" for a in range(3) for f in
                ("rank", "slice_rank0", "slice_rank1", "slice_rank2", "slice_rank3", "slice_rank4")]
    if data.get("schema") != "metaflip-learned-residual-v1" or data.get("features") != features:
        raise ValueError("model feature schema mismatch")
    arrays = data["arrays"]
    values = []
    for key, shape in (("mean", (18,)), ("scale", (18,)), ("w1", (18, 24)),
                       ("b1", (24,)), ("w2", (24, 1)), ("b2", (1,))):
        def flatten(value, dims):
            if not dims:
                if type(value) not in (int, float) or not math.isfinite(value) or abs(value) >= 1e6:
                    raise ValueError("invalid model number")
                return [float(value)]
            if not isinstance(value, list) or len(value) != dims[0]:
                raise ValueError(f"invalid shape for {key}")
            return [x for row in value for x in flatten(row, dims[1:])]
        values.extend(flatten(arrays[key], shape))
    if min(values[18:36]) < 1e-6:
        raise ValueError("invalid normalization scale")
    assert len(values) == 517
    return "MFLR1 sorted-slice-ranks 18 24 1\n" + "".join(format(x, ".17g") + "\n" for x in values)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    raw = args.model.read_bytes()
    body = export(json.loads(raw)).encode()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(body)
    print(json.dumps(dict(source_sha256=hashlib.sha256(raw).hexdigest(),
                          native_sha256=hashlib.sha256(body).hexdigest(), bytes=len(body))))
