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


def _raw_i64_decimal_assignment(prefix, array, expression, indent="    "):
    """Parse a potentially boxed decimal mask and store it through raw i64s.

    Seven-by-seven factors can set bit 48.  ``String#to_i`` represents those
    values as boxed BigInts, and assigning that method result directly to a
    typed i64 array currently crosses a boxed/raw lowering path incorrectly.
    Parsing two at-most-seven-digit chunks keeps every intermediate unboxed.
    """
    return "\n".join((
        f"{indent}{prefix}text = {expression}",
        f"{indent}{prefix}cut = {prefix}text.size() - 7",
        f"{indent}{prefix}mask = 0 ## i64",
        f"{indent}if {prefix}cut > 0",
        f"{indent}  {prefix}hi = {prefix}text.slice(0, {prefix}cut).to_i() ## i64",
        f"{indent}  {prefix}lo = {prefix}text.slice({prefix}cut, 7).to_i() ## i64",
        f"{indent}  {prefix}mask = {prefix}hi * 10000000 + {prefix}lo",
        f"{indent}if {prefix}cut <= 0",
        f"{indent}  {prefix}mask = {prefix}text.to_i()",
        f"{indent}{array} = {prefix}mask",
    ))


def _patch_raw_i64_host_path(src, seedcap):
    """Keep 7x7 host seed/result traffic on typed raw-i64 views."""
    old_parse = (
        "    baseu[ti2] = parts[field_base].to_i()\n"
        "    basev[ti2] = parts[field_base + 1].to_i()\n"
        "    basew[ti2] = parts[field_base + 2].to_i()"
    )
    parse = "\n".join((
        _raw_i64_decimal_assignment("u", "baseu[ti2]", "parts[field_base]"),
        _raw_i64_decimal_assignment("v", "basev[ti2]", "parts[field_base + 1]"),
        _raw_i64_decimal_assignment("w", "basew[ti2]", "parts[field_base + 2]"),
    ))
    assert old_parse in src, "cal2zone runtime-seed parser template changed"
    src = src.replace(old_parse, parse)

    allocation = "params = metal_buffer(device, 11 * 4)\n"
    views = (
        allocation +
        f"seed_us_view = metal_buffer_view(seed_us, 66, {seedcap} * ESCAPE_SEEDS) ## i64[]\n"
        f"seed_vs_view = metal_buffer_view(seed_vs, 66, {seedcap} * ESCAPE_SEEDS) ## i64[]\n"
        f"seed_ws_view = metal_buffer_view(seed_ws, 66, {seedcap} * ESCAPE_SEEDS) ## i64[]\n"
        "best_us_view = metal_buffer_view(best_us, 66, NW * CAP) ## i64[]\n"
        "best_vs_view = metal_buffer_view(best_vs, 66, NW * CAP) ## i64[]\n"
        "best_ws_view = metal_buffer_view(best_ws, 66, NW * CAP) ## i64[]\n"
    )
    assert allocation in src, "cal2zone Metal allocation template changed"
    src = src.replace(allocation, views)

    for axis in ("u", "v", "w"):
        old = (f"metal_buffer_write_i64(seed_{axis}s, soff + ii, "
               f"seed{axis}[soff + ii])")
        new = f"seed_{axis}s_view[soff + ii] = seed{axis}[soff + ii]"
        assert old in src, f"cal2zone seed-{axis} write template changed"
        src = src.replace(old, new)

        old = (f"metal_buffer_read_i64(best_{axis}s, "
               "bestthread * CAP + di)")
        new = f"best_{axis}s_view[bestthread * CAP + di]"
        assert old in src, f"cal2zone best-{axis} read template changed"
        src = src.replace(old, new)

    for axis in ("u", "v", "w"):
        src = src.replace(
            f"metal_buffer_read_i64(buf{axis}, baseoff + t)",
            f"buf{axis}[baseoff + t]",
        )
    old_verify = ("verify_buf(best_us, best_vs, best_ws, bestthread * CAP, "
                  "localmin, 555, nn, mm, pp)")
    new_verify = ("verify_buf(best_us_view, best_vs_view, best_ws_view, "
                  "bestthread * CAP, localmin, 555, nn, mm, pp)")
    assert old_verify in src, "cal2zone host verification template changed"
    src = src.replace(old_verify, new_verify)
    old_error = ("verify_buf_error(best_us, best_vs, best_ws, bestthread * CAP, "
                 "localmin, 555, nn, mm, pp)")
    new_error = ("verify_buf_error(best_us_view, best_vs_view, best_ws_view, "
                 "bestthread * CAP, localmin, 555, nn, mm, pp)")
    assert old_error in src, "cal2zone diagnostic verification template changed"
    return src.replace(old_error, new_error)


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

    src = src.replace(
        "# 5x5 factors are 25 bits.  The old 65535 modulus silently confined\n"
        "          # every plus move to 16 bits and left nine coordinates unsampled.",
        f"# <{n},{m},{p}> factors span {AB}/{BB}/{CB} bits.  Sample the "
        f"{maxbits}-bit envelope, then trim it to the selected axis.",
    )
    src = src.replace(
        "# supports square 3x3..7x7, whose largest configured CAP is below 512.",
        f"# is specialized for <{n},{m},{p}>; its configured CAP is below 512.",
    )

    # The square fleet keeps its established escape ordering.  Rectangular
    # lanes are often allocated in much smaller slices, where grouping a full
    # baserank of U splits before V and W starves two axes.  Interleave axes and
    # advance each axis through its own deterministic target permutation.
    if n != m or m != p:
        old_escape_map = (
            "      target = (sid * 37 + rd * 17) % baserank\n"
            "      axis = (sid / baserank) % 3"
        )
        new_escape_map = (
            "      axis = sid % 3\n"
            "      escape_index = sid / 3\n"
            "      target = (escape_index * 37 + axis * 13 + rd * 17) % baserank"
        )
        assert old_escape_map in src, "cal2zone split-escape map changed"
        src = src.replace(old_escape_map, new_escape_map)

    # Rectangular factors have different widths.  The historical square
    # template sampled one common max-width mask for every plus move, which
    # can introduce out-of-range coordinates on the shorter axes.  Keep the
    # inexpensive common RNG, then trim it after the random axis is known.
    # For square tensors all three masks are equal, so generated square code
    # retains identical behavior.
    axis_line = "paxis = ((state % 3) + 3) % 3"
    axis_masks = f"""paxis = ((state % 3) + 3) % 3
          if paxis == 0
            u1 = u1 & {(1 << AB) - 1}
          if paxis == 1
            u1 = u1 & {(1 << BB) - 1}
          if paxis == 2
            u1 = u1 & {(1 << CB) - 1}
          if u1 == 0
            u1 = 1"""
    assert src.count(axis_line) == 1
    src = src.replace(axis_line, axis_masks)

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

        # A 7x7 mask may set bit 48, above the current inline-integer range.
        # Keep parsing and Metal buffer access raw end-to-end.  The condition is
        # width-based so equally wide rectangular formats receive the same fix;
        # square sizes 3 through 6 remain byte-for-byte unchanged.
        if maxbits >= 49:
            src = _patch_raw_i64_host_path(src, seedcap)

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
