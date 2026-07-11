"""Specialize the cooperative SIMD-group flip walker for square n x n x n.

The checked-in template is the useful 5x5/i32 executable.  This generator is
primarily needed for 6x6, whose 36-bit factors require the native Tungsten
``gpu.shared_i64`` and Metal ``long`` buffer path.

Usage:
    python3 gpu_simdgroup_gen.py N CAP OUT.w METAL.ll

Compile the result with ``TUNGSTEN_LL_PATH=METAL.ll bin/tungsten ... OUT.w``;
the generated host reads the sibling ``METAL.metal`` sidecar.
"""

from __future__ import annotations

import os
import re
import sys


SOURCE = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "flipgraph_gpu_simdgroup.w")
)


MASK_BUFFERS = (
    "work_us", "work_vs", "work_ws",
    "best_us", "best_vs", "best_ws",
    "seed_us", "seed_vs", "seed_ws",
)


def generate(n: int, cap: int, metal_ll: str) -> str:
    if n < 2:
        raise ValueError("n must be at least 2")
    bits = n * n
    if bits > 62:
        raise ValueError(f"{n}x{n} needs {bits} factor bits; signed i64 supports 62")
    use_i64 = bits > 30
    mask_bytes = 8 if use_i64 else 4
    hash_size = 512 if use_i64 else 256
    with open(SOURCE, encoding="utf-8") as f:
        src = f.read()

    for name in ("sus", "svs", "sws"):
        old = f"{name} = gpu.shared_i32(112)"
        new = f"{name} = gpu.shared_{'i64' if use_i64 else 'i32'}({cap})"
        assert old in src, old
        src = src.replace(old, new)
    old = "schanged = gpu.shared_i32(6)"
    assert old in src
    src = src.replace(old, f"schanged = gpu.shared_{'i64' if use_i64 else 'i32'}(6)")
    src = src.replace("heads = gpu.shared_i32(768)",
                      f"heads = gpu.shared_i32({3 * hash_size})")
    src = src.replace("nexts = gpu.shared_i32(336)",
                      f"nexts = gpu.shared_i32({3 * cap})")
    if hash_size != 256:
        src = re.sub(r"\b768\b", str(3 * hash_size), src)
        src = re.sub(r"\b256\b", str(hash_size), src)
        src = re.sub(r"\b255\b", str(hash_size - 1), src)

    fullmask = (1 << bits) - 1
    old_rng = "part = (((state % 33554431) + 33554431) % 33554431) + 1"
    if use_i64:
        new_rng = (
            "part = state & 2147483647\n"
            "            state = state * 1103515245 + 12345\n"
            f"            part = ((part << 31) ^ (state & 2147483647)) & {fullmask}\n"
            "            if part == 0\n"
            "              part = 1"
        )
    else:
        new_rng = f"part = (((state % {fullmask}) + {fullmask}) % {fullmask}) + 1"
    assert old_rng in src
    src = src.replace(old_rng, new_rng)

    if use_i64:
        for name in MASK_BUFFERS:
            old = f"## i32[]: {name}"
            assert old in src, old
            src = src.replace(old, f"## i64[]: {name}")
        for name in ("part", "cu1", "cv1", "cw1", "cu2", "cv2", "cw2", "px", "oldfactor"):
            old = f"{name} = 0 ## i32"
            assert old in src, old
            src = src.replace(old, f"{name} = 0 ## i64")
        for name in ("seed_us", "seed_vs", "seed_ws"):
            src = src.replace(
                f"metal_buffer_write_i32({name}", f"metal_buffer_write_i64({name}"
            )
        for name in ("best_us", "best_vs", "best_ws"):
            src = src.replace(
                f"metal_buffer_read_i32({name}", f"metal_buffer_read_i64({name}"
            )

    seeds = {
        5: "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt",
        6: "benchmarks/matmul/metaflip/matmul_6x6_rank153_d2508_gf2.txt",
    }
    default_seed = seeds.get(n, f"/tmp/matmul_{n}x{n}_seed.txt")
    replacements = {
        "CAP = 112": f"CAP = {cap}",
        "MASK_BYTES = 4": f"MASK_BYTES = {mask_bytes}",
        "MODE = 0": f"MODE = {1 if n >= 6 else 0}",
        "nn = 5\nmm = 5\npp = 5": f"nn = {n}\nmm = {n}\npp = {n}",
        'seedpath = "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt"':
            f'seedpath = "{default_seed}"',
        'outpath = "/tmp/flipgraph_gpu_simdgroup_best_555.txt"':
            f'outpath = "/tmp/flipgraph_gpu_simdgroup_best_{n}{n}{n}.txt"',
        'msl = read_file("benchmarks/matmul/flipgraph_gpu_simdgroup.metal")':
            f'msl = read_file("{metal_ll.removesuffix(".ll")}.metal")',
    }
    for old, new in replacements.items():
        assert old in src, old
        src = src.replace(old, new)
    return src


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print("usage: gpu_simdgroup_gen.py N CAP OUT.w METAL.ll", file=sys.stderr)
        return 2
    n = int(argv[1])
    cap = int(argv[2])
    out = argv[3]
    metal_ll = argv[4]
    src = generate(n, cap, metal_ll)
    with open(out, "w", encoding="utf-8") as f:
        f.write(src)
    bits = n * n
    hash_size = 512 if bits > 30 else 256
    mask_bytes = 8 if bits > 30 else 4
    shared = 3 * cap * mask_bytes + 6 * mask_bytes + 4 * (3 * hash_size + 3 * cap)
    print(
        f"wrote {out}: {n}x{n}, {'i64' if bits > 30 else 'i32'}, "
        f"scheme shared memory {shared} bytes",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
