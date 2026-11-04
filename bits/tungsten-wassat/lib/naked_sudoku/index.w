# Original-clause index for the bounded naked-single certificate checker.
# No auxiliary variable is trusted by its identifier: every use below needs
# an original implication, with exact collision checks on the clause index.
+ WassatNakedSudoku
  ro :meta

  -> new(formula, stop, deadline, meta)
    @nv = formula["nvars"]; @nc = formula["flat_ncl"]; @nl = formula["flat_nlits"]
    bind(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], stop, meta)
    @deadline = deadline; @work = 0; @epoch = 0; @qepoch = 0; @mepoch = 0
    @nt = 0; @taut = false; @rank = 0; @n = 0; @cells = 0
    @steps = 0; @nclues = 0; @xend = 0; @yend = 0; @zmax = 0
    @int_end = @nc; @kernel_state = nil

  -> bind(@lits, @offs, @lens, @stop, @meta) (i64[] i64[] i64[] i64[] i64[])
    0

  -> abs(v) (i64) i64
    v < 0 ? 0 - v : v

  -> li(v) (i64) i64
    v < 0 ? (0 - v) * 2 + 1 : v * 2

  -> poll
    @meta[1] += 1
    @meta[0] = 1 if wassat_stop_load(@stop) != 0
    @meta[0] = 2 if @meta[0] == 0 && @deadline > 0 && clock_ms() >= @deadline
    @meta[0] != 0

  -> visit
    @work += 1
    @meta[0] = 3 if @work > 1000000000
    (@work & 1023) == 0 ? poll : @meta[0] != 0

  # Signed machine arithmetic, including the wraparound multiplications.
  -> mix(v) (i64) i64
    h = v ## i64
    h = (h ^ (h >> 30)) * -4658895280553007687
    h = (h ^ (h >> 27)) * -7723592293110705685
    # Method results cross a boxed boundary. Keep the return in the immediate
    # integer range: every bucket mask is below 2^22, so discarding these high
    # bits preserves bucket selection while avoiding one BigInt per literal.
    (h ^ (h >> 31)) & 2147483647

  -> build_index
    return false if poll
    size = 1
    while size < @nc
      size *= 2
    @hmask = size - 1; @heads = i32[size]; @hnext = i32[@nc]
    @ofirst = i32[2 * @nv + 2]; @bfirst = i32[2 * @nv + 2]
    @onext = i32[@nl]; @bnext = i32[@nl]; @oci = i32[@nl]
    @ocount = i32[2 * @nv + 2]; @cseen = i32[@nc]
    @qmark = i32[2 * @nv + 2]; @mseen = i32[2 * @nv + 2]
    @query = i32[1024]; @ta = i32[32]; @tb = i32[32]
    @ts = i8[32]; @tried = i8[32]
    @meta[30] += 4 * (size + 2 * @nc + 3 * @nl + 5 * (2 * @nv + 2) + 1088) + 64
    ci = @nc - 1
    while ci >= 0
      return false if visit
      o = @offs[ci]; len = @lens[ci]; h = 0 ## i64
      j = len - 1
      while j >= 0
        v = @lits[o + j]; h += mix(v); p = o + j; k = li(v)
        @oci[p] = ci; @onext[p] = @ofirst[k]; @ofirst[k] = p + 1; @ocount[k] += 1
        if len == 2
          @bnext[p] = @bfirst[k]; @bfirst[k] = p + 1
        j -= 1
      slot = h & @hmask
      @hnext[ci] = @heads[slot]; @heads[slot] = ci + 1
      ci -= 1
    @meta[2] = @nc; @meta[3] = @nl
    @kernel_state = i64[16]
    @meta[30] += 128
    @kernel_state[0] = @work; @kernel_state[1] = @deadline
    @kernel_state[2] = @xend; @kernel_state[3] = @zmax
    @kernel_state[4] = @hmask; @kernel_state[5] = @int_end
    @kernel_state[6] = @nv; @kernel_state[12] = @nl
    true

  # @query holds a DISTINCT clause. Reject duplicate originals rather than
  # confusing a multiset/hash collision with the requested set of literals.
  -> has_clause(n) (i64) bool
    wassat_naked_k_has_clause(@kernel_state, @meta, @stop, @lits, @offs, @lens, @heads, @hnext, @qmark, @mseen, @query, n)

  -> begin_query
    @nt = 0; @taut = false
    0

  -> term(a, b = 0) (i64 i64)
    if @nt >= 32
      @meta[0] = 3
      return 0
    @ta[@nt] = a; @tb[@nt] = b; @ts[@nt] = b == 0 ? 1 : 2; @nt += 1
    0

  -> require_query
    @kernel_state[10] = @nt
    @kernel_state[11] = @taut ? 1 : 0
    wassat_naked_k_require_query(@kernel_state, @meta, @stop, @lits, @offs, @lens, @domain, @heads, @hnext, @ofirst, @onext, @bfirst, @bnext, @oci, @ocount, @cseen, @qmark, @mseen, @query, @ta, @tb, @ts, @tried)
