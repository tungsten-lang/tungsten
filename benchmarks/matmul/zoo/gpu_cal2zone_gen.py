"""Parameterized generator for the GPU cal2zone relay kernel, derived from
benchmarks/matmul/flipgraph_gpu_cal2zone.w (which is hand-fixed for 5x5:
CAP=140, WPG=16, seed-array-cap=160 — too small for 6x6/7x7, where even the
SEED itself (153 / 343 terms) would already overflow those buffers).

Four things scale together and must stay consistent:
  - CAP        max terms per thread (must exceed naive rank with wander slack)
  - WPG        walkers per threadgroup (interleave stride — every per-walker
               array index in the kernel is `i * WPG + ltid`; the ORIGINAL
               source has this baked in as a literal 16 in ~30 places)
  - mask width  i32 through 30 bits; i64 above that (6x6 needs 36 bits)
  - shared mem = CAP * WPG * mask_bytes * 3 arrays (us/vs/ws), <= 32768
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
import os

SOURCE = os.path.abspath(os.path.join(
    os.path.dirname(__file__), "..", "flipgraph_gpu_cal2zone.w"))


def gen(n, m, p, cap, wpg, seedcap, metal_ll_path, nw=4096, steps=500000, rounds=1000000,
        margin=4, wqwork=150000, wqwander=60000, wthr0=7):
    AB, BB, CB = n * m, m * p, n * p
    maxbits = max(AB, BB, CB)
    assert maxbits <= 62, (
        f"<{n},{m},{p}> needs {maxbits}-bit masks; signed i64 GPU masks allow 62")
    # Keep sign-bit cases out of the i32 walker.  They make the signed LCG and
    # popcount loop need special cases, while i64 is already required by 6x6.
    use_i64 = maxbits > 30
    mask_bytes = 8 if use_i64 else 4
    shared_bytes = cap * wpg * mask_bytes * 3
    assert shared_bytes <= 32768, (
        f"CAP={cap} WPG={wpg} needs {shared_bytes}B shared mem, over the 32768B Metal limit")
    assert nw % wpg == 0, f"NW={nw} must be a multiple of WPG={wpg}"

    with open(SOURCE) as stream:
        src = stream.read()

    # Every per-walker interleave index in the kernel body is `<expr> * 16 + ltid`
    # (WPG baked in as a literal). Replace precisely that pattern, not any other
    # bare "16" that might appear (there are none elsewhere in this file, but be
    # surgical rather than a blanket string replace).
    src, nsub = re.subn(r'\* 16 \+ ltid', f'* {wpg} + ltid', src)
    assert nsub == 133, f"expected exactly 133 stride substitutions, got {nsub} — source may have changed"

    shared_kind = "shared_i64" if use_i64 else "shared_i32"
    src = src.replace("sus = gpu.shared_i32(2240)", f"sus = gpu.{shared_kind}({cap * wpg})")
    src = src.replace("svs = gpu.shared_i32(2240)", f"svs = gpu.{shared_kind}({cap * wpg})")
    src = src.replace("sws = gpu.shared_i32(2240)", f"sws = gpu.{shared_kind}({cap * wpg})")

    fullmask = (1 << maxbits) - 1
    old_rng = "u1 = (((state % 33554431) + 33554431) % 33554431) + 1"
    if use_i64:
        new_rng = """u1 = state & 2147483647
          state = state * 1103515245 + 12345
          u1 = ((u1 << 31) ^ (state & 2147483647)) & %d
          if u1 == 0
            u1 = 1""" % fullmask
    else:
        new_rng = f"u1 = (((state % {fullmask}) + {fullmask}) % {fullmask}) + 1"
    assert old_rng in src
    src = src.replace(old_rng, new_rng)

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
    assert nsub2 == 11, f"expected 11 occurrences of the seed-array-cap 160, got {nsub2}"

    if use_i64:
        # Nine buffers carry masks; st and params deliberately remain i32.
        for name in ("work_us", "work_vs", "work_ws", "best_us", "best_vs",
                     "best_ws", "seed_us", "seed_vs", "seed_ws"):
            src = src.replace(f"## i32[]: {name}", f"## i64[]: {name}")
        src = src.replace("u1 = 0 ## i32", "u1 = 0 ## i64")
        src = src.replace("pz = 0 ## i32", "pz = 0 ## i64")

        # Device mask buffers and their host accessors widen together.
        src = src.replace("NW * CAP * 4", "NW * CAP * 8")
        src = src.replace(f"{seedcap} * ESCAPE_SEEDS * 4",
                          f"{seedcap} * ESCAPE_SEEDS * 8")
        for name in ("seed_us", "seed_vs", "seed_ws"):
            src = src.replace(f"metal_buffer_write_i32({name}",
                              f"metal_buffer_write_i64({name}")
        for name in ("bufu", "bufv", "bufw", "best_us", "best_vs", "best_ws"):
            src = src.replace(f"metal_buffer_read_i32({name}",
                              f"metal_buffer_read_i64({name}")

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
    print(f"wrote {outpath} ({'i64' if max(n*m,m*p,n*p)>30 else 'i32'} masks, "
          f"shared mem {shared_bytes}/32768 bytes, "
          f"metal sidecar will be {metal_ll_path.replace('.ll', '.metal')})", file=sys.stderr)
