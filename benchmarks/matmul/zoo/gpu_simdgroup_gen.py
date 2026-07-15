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


def _raw_i64_decimal_assignment(prefix: str, array: str, expression: str) -> str:
    """Parse a potentially boxed decimal mask into a raw i64 array slot."""
    return "\n".join((
        f"  {prefix}text = {expression}",
        f"  {prefix}cut = {prefix}text.size() - 7",
        f"  {prefix}mask = 0 ## i64",
        f"  if {prefix}cut > 0",
        f"    {prefix}hi = {prefix}text.slice(0, {prefix}cut).to_i() ## i64",
        f"    {prefix}lo = {prefix}text.slice({prefix}cut, 7).to_i() ## i64",
        f"    {prefix}mask = {prefix}hi * 10000000 + {prefix}lo",
        f"  if {prefix}cut <= 0",
        f"    {prefix}mask = {prefix}text.to_i()",
        f"  {array} = {prefix}mask",
    ))


def _patch_raw_i64_host_path(src: str) -> str:
    """Keep 7x7 decimal parsing and Metal traffic raw end to end.

    A 7x7 factor can set bit 48.  ``String#to_i`` then produces a boxed
    BigInt, while direct assignment into a typed i64 array currently crosses a
    boxed/raw lowering path that truncates the value.  Two small decimal chunks
    and typed Metal buffer views avoid that path in the generated Tungsten.
    """
    old_parse = (
        "  seedu[ii] = parts[colbase].to_i()\n"
        "  seedv[ii] = parts[colbase + 1].to_i()\n"
        "  seedw[ii] = parts[colbase + 2].to_i()\n"
    )
    replacement = "\n".join((
        _raw_i64_decimal_assignment("u", "seedu[ii]", "parts[colbase]"),
        _raw_i64_decimal_assignment("v", "seedv[ii]", "parts[colbase + 1]"),
        _raw_i64_decimal_assignment("w", "seedw[ii]", "parts[colbase + 2]"),
    )) + "\n"
    assert old_parse in src, "SIMD-group runtime-seed parser template changed"
    src = src.replace(old_parse, replacement)

    allocation = "params = metal_buffer(device, 7 * 4)\n"
    views = (
        allocation +
        "seed_us_view = metal_buffer_view(seed_us, 66, CAP) ## i64[]\n"
        "seed_vs_view = metal_buffer_view(seed_vs, 66, CAP) ## i64[]\n"
        "seed_ws_view = metal_buffer_view(seed_ws, 66, CAP) ## i64[]\n"
        "best_us_view = metal_buffer_view(best_us, 66, GROUPS * CAP) ## i64[]\n"
        "best_vs_view = metal_buffer_view(best_vs, 66, GROUPS * CAP) ## i64[]\n"
        "best_ws_view = metal_buffer_view(best_ws, 66, GROUPS * CAP) ## i64[]\n"
    )
    assert allocation in src, "SIMD-group Metal allocation template changed"
    src = src.replace(allocation, views)
    for axis in ("u", "v", "w"):
        src = src.replace(
            f"  metal_buffer_write_i64(seed_{axis}s, ii, seed{axis}[ii])",
            f"  seed_{axis}s_view[ii] = seed{axis}[ii]",
        )
        src = src.replace(
            f"metal_buffer_read_i64(best_{axis}s, bestgroup * CAP + ii)",
            f"best_{axis}s_view[bestgroup * CAP + ii]",
        )
    return src


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
        if bits >= 49:
            src = _patch_raw_i64_host_path(src)

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
