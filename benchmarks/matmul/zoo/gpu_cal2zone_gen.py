"""Parameterized generator for the GPU cal2zone relay kernel, derived from
benchmarks/matmul/flipgraph_gpu_cal2zone.w (which is hand-fixed for 5x5:
CAP=140, WPG=16, seed-array-cap=160 — too small for 6x6/7x7, where even the
SEED itself (153 / 343 terms) would already overflow those buffers).

Three things scale together and must stay consistent:
  - CAP        max terms per thread (must exceed naive rank with wander slack)
  - WPG        walkers per threadgroup (interleave stride — every per-walker
               array index in the kernel is `i * WPG + ltid`; the ORIGINAL
               source has this baked in as a literal 16 in ~30 places)
  - shared mem = CAP * WPG * 4 bytes * 3 arrays (us/vs/ws), must stay <= 32768
               (Metal's per-threadgroup shared-memory limit)
  - SEEDCAP    size of the seed_us/vs/ws device buffers, must exceed the
               largest rank ever loaded as a seed (the naive rank, since the
               coordinator's canonical file starts there and only shrinks)

Usage: python3 gpu_cal2zone_gen.py <n> <m> <p> <cap> <wpg> <seedcap> <outpath.w> <metalpath.ll>
Emits the .w source to outpath, with its `msl = read_file(...)` line pointing
at whatever metalpath's sibling .metal will be (build by setting
TUNGSTEN_LL_PATH=<metalpath.ll> before `bin/tungsten -o <bin> <outpath.w>` —
the compiler writes both metalpath.ll and metalpath.metal).
"""
import re
import sys

SOURCE = "/Users/erik/tungsten/benchmarks/matmul/flipgraph_gpu_cal2zone.w"


def gen(n, m, p, cap, wpg, seedcap, metal_ll_path, nw=4096, steps=500000, rounds=1000000,
        margin=4, wqwork=150000, wqwander=60000, wthr0=7):
    # HARD ceiling, confirmed empirically 2026-07-05: the kernel's masks are
    # i32 (`## i32[]: work_us` etc, `gpu.shared_i32`) — max(AB,BB,CB) > 32
    # silently truncates mask bits, producing corrupted schemes that (mostly)
    # get caught by verify_buf as an invalid candidate rather than a fake
    # improvement, but are NOT usable. Isolated by bisection: WPG=8 alone and
    # CAP=260 alone both ran clean at 5x5 (25-bit masks); only the 6x6 format
    # (36-bit masks) broke, deterministically, every round. This is a kernel
    # rewrite (i64 or two-limb masks), not a CAP/WPG tuning problem — do not
    # bypass this assertion without doing that rewrite first.
    AB, BB, CB = n * m, m * p, n * p
    assert max(AB, BB, CB) <= 32, (
        f"<{n},{m},{p}> needs {max(AB,BB,CB)}-bit masks — this i32-mask kernel "
        f"maxes out at 32 bits (n<=5 for square formats). Needs an i64/two-limb "
        f"mask rewrite; CAP/WPG tuning cannot fix this.")
    shared_bytes = cap * wpg * 4 * 3
    assert shared_bytes <= 32768, (
        f"CAP={cap} WPG={wpg} needs {shared_bytes}B shared mem, over the 32768B Metal limit")
    assert nw % wpg == 0, f"NW={nw} must be a multiple of WPG={wpg}"

    src = open(SOURCE).read()

    # Every per-walker interleave index in the kernel body is `<expr> * 16 + ltid`
    # (WPG baked in as a literal). Replace precisely that pattern, not any other
    # bare "16" that might appear (there are none elsewhere in this file, but be
    # surgical rather than a blanket string replace).
    src, nsub = re.subn(r'\* 16 \+ ltid', f'* {wpg} + ltid', src)
    assert nsub == 130, f"expected exactly 130 stride substitutions, got {nsub} — source may have changed"

    src = src.replace("sus = gpu.shared_i32(2240)", f"sus = gpu.shared_i32({cap * wpg})")
    src = src.replace("svs = gpu.shared_i32(2240)", f"svs = gpu.shared_i32({cap * wpg})")
    src = src.replace("sws = gpu.shared_i32(2240)", f"sws = gpu.shared_i32({cap * wpg})")

    src = src.replace("NW = 4096", f"NW = {nw}")
    src = src.replace("WPG = 16", f"WPG = {wpg}")
    src = src.replace("CAP = 140", f"CAP = {cap}")
    src = src.replace("STEPS = 500000", f"STEPS = {steps}")
    src = src.replace("ROUNDS = 1000000", f"ROUNDS = {rounds}")
    src = src.replace("MARGIN = 4", f"MARGIN = {margin}")
    src = src.replace("WQWORK = 150000", f"WQWORK = {wqwork}")
    src = src.replace("WQWANDER = 60000", f"WQWANDER = {wqwander}")
    src = src.replace("WTHR0 = 7", f"WTHR0 = {wthr0}")

    src = src.replace('nn = 5\nmm = 5\npp = 5', f'nn = {n}\nmm = {m}\npp = {p}')

    # Seed-array device buffers + host-side staging arrays: hardcoded 160.
    src, nsub2 = re.subn(r'\b160\b', str(seedcap), src)
    assert nsub2 == 6, f"expected 6 occurrences of the seed-array-cap 160, got {nsub2}"

    metal_path = metal_ll_path.replace(".ll", ".metal")
    src = src.replace(
        'msl = read_file("benchmarks/matmul/flipgraph_gpu_cal2zone.metal")',
        f'msl = read_file("{metal_path}")')

    # Default seedpath/gpubestpath are always overridden by argv in our fleet
    # launcher, but keep them format-sane rather than leftover 5x5 defaults.
    src = re.sub(
        r'seedpath = "benchmarks/matmul/metaflip/runs/run_555/current_best\.txt"\n'
        r'gpubestpath = "benchmarks/matmul/metaflip/runs/run_555/gpu_best\.txt"',
        f'seedpath = "benchmarks/matmul/metaflip/runs/run_{n}{m}{p}/current_best.txt"\n'
        f'gpubestpath = "benchmarks/matmul/metaflip/runs/run_{n}{m}{p}/gpu_best.txt"',
        src)

    return src, shared_bytes


if __name__ == "__main__":
    n, m, p, cap, wpg, seedcap = (int(x) for x in sys.argv[1:7])
    outpath, metal_ll_path = sys.argv[7], sys.argv[8]
    src, shared_bytes = gen(n, m, p, cap, wpg, seedcap, metal_ll_path)
    with open(outpath, "w") as f:
        f.write(src)
    print(f"wrote {outpath} (shared mem {shared_bytes}/32768 bytes, "
          f"metal sidecar will be {metal_ll_path.replace('.ll', '.metal')})", file=sys.stderr)
