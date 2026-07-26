# SmallArray
#
# Frozen, stack-allocatable, packed array. Up to 255 elements.
# Element type chosen at construction (u4..f64, w64).
#
# No start/cap (size = cap, no shift). No owned/pooled/view flags
# (never malloc'd, never aliased into a borrow contract). First byte
# stores the full ebits code, including extended signed/float sentinels.
#
# Use cases: tensor shapes, strides, top-k indices, kernel scalar args,
# memoization keys.
#
# ── Vectorization notes (measured: clang -O3 -march=native, Apple Silicon;
#    element-wise map loop `p[i] = p[i] + 1`, objdump-verified NEON) ──
#
# Element-count cutoff above which clang auto-vectorizes an element-wise loop
# (below it: fully-unrolled or scalar — still fast for tiny arrays):
#     ebits          vectorizes at N >=
#     i8  / u8              64
#     i16 / u16 / f16       32
#     i32 / u32 / f32       32
#     i64 / u64 / f64       32
#   (i8 needs more elements — 16 lanes/vector, so more iterations to pay off.
#    The 32-row types were not swept below 32; the true boundary is <= 32.
#    These are clang cost-model thresholds and can shift with the toolchain.)
# When it fires, vectorization is ~3-12x faster (memory-bandwidth bound).
#
# Payload ALIGNMENT does NOT matter here: a 4-byte header (payload 4-aligned)
# and an 8-byte header (8-aligned) vectorize identically and run at the same
# speed — ARM64 executes unaligned NEON at full rate. So padding WSmallArray's
# 2-byte header for alignment buys nothing on this target.
#
# VECTORIZATION (fixed): rvalue element READS once fell to a `w_index_raw_i64`
# runtime CALL (a call in the loop body defeats the vectorizer) while WRITES
# already used the inline op. Reads now route through small_array_get_inline too
# (as typed WArray reads do), so promoted small-array element loops vectorize —
# not alignment/padding/TBAA (TBAA is on the small_array ops; alignment and the
# boxed-pointer inttoptr pattern both vectorize fine in isolation).
#
# HEADERLESS (fixed): a non-escaping function-local stack-promoted small array
# is now a bare `[N x T]` alloca — no 2-byte header, and the pointer is never
# boxed into a WValue — so LLVM SROA can promote a constant-index buffer to
# registers. `.size` folds to the compile-time N. Escaping / top-level / heap
# small arrays keep this full headerful WSmallArray layout.

+ SmallArray
  is Enumerable

  - data (WSmallArray)
      u8   ebits
      u8   size
      u8[] slots

  -> __enumerable_iteration_mode
    1

  # Header size is a u8, so it always fits the immediate-Integer payload.
  # Construct the canonical WValue tag in source and avoid an out-of-line
  # w_int call on every public query.
  -> size
    n = $size ## i64
    tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
    wvalue_from_bits((tag | n) ## i64)

  # SmallArray is frozen: capacity is exactly its header size.
  -> cap
    n = $size ## i64
    tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
    wvalue_from_bits((tag | n) ## i64)

  -> empty?
    n = $size ## i64
    if n == 0
      return true
    false

  -> each/&
    $size -> &(self[i]) : self

  -> sort(&)
    if block_given?
      to_a.sort -> (a, b)
        &(a, b)
    else
      to_a.sort

  # Delegate to Array's working shuffle (the former `*opts` splat could not
  # pack on the compiled/self-hosted engines; a bare `shuffle` needs none).
  -> shuffle
    to_a.shuffle

  -> rotate(count = 1)
    to_a.rotate(count)
