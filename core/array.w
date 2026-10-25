# Array
#
# Ordered, mutable collection of typed values. Element type chosen at
# construction; when ebits = w64 holds polymorphic WValues (the old "untyped"
# array behavior). Up to 2^32 elements.
#
# Literal syntax:
#   [1, 2, 3]         # ebits = w64
#   ["a", "b", "c"]   # ebits = w64
#   u8[10]            # ebits = u8
#   f32[256]          # ebits = f32
#
# -- Access --
#
#   arr[i]            Index (0-based, negative wraps from end)
#   arr[i] = val      Set element at index
#   arr.first         First element, or nil if empty
#   arr.last          Last element, or nil if empty
#   arr.slice(i, n)   Sub-array of n elements starting at i
#
# -- Mutation --
#
#   arr.push(val)     Append val, return self
#   arr.pop           Remove and return last element (nil if empty)
#   arr.shift         Remove and return first element (nil if empty)
#   arr.unshift(val)  Prepend val, return self
#
# -- Query --
#
#   arr.size          Number of elements
#   arr.size        Alias for size
#   arr.empty?        True if size == 0
#   arr.include?(val) True if val is in the array
#
# 0 <= start
# 0 <= size
# start + size <= cap

+ Array
  # array[i] = val, does not check bounds or resize, array.push(val) does
  is Enumerable

  - data (WArray)
      u8    flags
      u8    ebits
      u8[2] _pad
      u32   start
      u32   size
      u32   cap
    * u8[]  slots

  runtime :[], :[]=

  -> __enumerable_iteration_mode
    1

  # size/cap are u32 header fields and therefore always fit the immediate Int
  # payload. Build the canonical tag directly instead of calling w_int.
  -> size
    n = $size ## i64
    tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
    wvalue_from_bits((tag | n) ## i64)

  -> cap
    n = $cap ## i64
    tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
    wvalue_from_bits((tag | n) ## i64)

  -> empty?
    n = $size ## i64
    if n == 0
      return true
    false

  -> clear
    $start = 0
    $size = 0
    self

  # Indexing stays behind Array's ebits-aware storage boundary. That preserves
  # shifted starts, borrowed views, bool decoding, signed packed integers,
  # floats, and polymorphic WValues while the branch/query logic lives here.
  -> first
    n = $size ## i64
    if n == 0
      return nil
    self[0]

  -> last
    n = $size ## i64
    if n == 0
      return nil
    self[n - 1]

  # Storage-side half of Enumerable#flat_map. Keeping the indexed copy here
  # avoids allocating and invoking a second iterator closure for every nested
  # Array while the flattening algorithm itself remains in Enumerable.
  -> __enumerable_append_to(out)
    n = $size ## i64
    i = 0
    while i < n
      out.push(self[i])
      i += 1
    out

  # Array#[] handles the pointer math (e.g. $start + sizeof($ebits) * i)
  -> each/&
    $size -> &(self[i]) : self

  -> to_a
    self

  # Snapshot the receiver size once: indexed reads and pushes into the fresh
  # result cannot mutate self, so rereading the header on every backedge only
  # adds work. Both methods deliberately return ordinary polymorphic Arrays,
  # matching the former runtime handlers for typed and view receivers.
  -> compact
    n = $size ## i64
    if n == 0
      return []
    keep = 0
    i = 0
    while i < n
      if self[i] != nil
        keep += 1
      i += 1
    if keep == 0
      return []
    out = Array.new(keep)
    if keep == n
      i = 0
      while i < n
        out[i] = self[i]
        i += 1
      return out
    j = 0
    i = 0
    while i < n
      value = self[i]
      if value != nil
        out[j] = value
        j += 1
      i += 1
    out

  -> dup
    n = $size ## i64
    if n == 0
      return []
    out = Array.new(n)
    i = 0
    while i < n
      out[i] = self[i]
      i += 1
    out

  # take/drop are ports of the former runtime IC handlers,
  # keeping their exact clamping semantics (negative counts clamp to 0,
  # oversized counts to $size). Like compact/dup they return ordinary
  # polymorphic Arrays for typed and view receivers. Benchmarked at parity
  # with the retired C handlers; see benchmarks/builtins/.
  -> take(count)
    n = $size ## i64
    k = count ## i64
    if k <= 0 || n == 0
      return []
    if k > n
      k = n
    out = Array.new(k)
    i = 0
    while i < k
      out[i] = self[i]
      i += 1
    out

  -> drop(count)
    n = $size ## i64
    k = count ## i64
    if k < 0
      k = 0
    if k >= n
      return []
    m = n - k
    out = Array.new(m)
    i = 0
    while i < m
      out[i] = self[k + i]
      i += 1
    out

  -> reverse
    n = $size ## i64
    if n == 0
      return []
    out = Array.new(n)
    i = 0
    j = n - 1
    while i < n
      out[i] = self[j]
      i += 1
      j -= 1
    out

  # Remove and return the element at idx, shifting the tail down and
  # shrinking by one — the former C IC handler's exact semantics: a negative
  # idx wraps from the end, and an out-of-range idx (after wrap) returns nil
  # without mutating. The shift writes through `[]=` (direct-call
  # w_array_set/w_array_set_i64 in an Array class body) and the size
  # decrement rides on `pop`.
  -> delete_at(idx)
    n = $size ## i64
    i = idx ## i64
    if i < 0
      i = n + i
    if i < 0 || i >= n
      return nil
    removed = self[i]
    last = n - 1
    while i < last
      self[i] = self[i + 1]
      i += 1
    pop
    removed

  # Value-copy of a sub-range (the copying counterpart to the zero-copy
  # `slice` view), ported from the former C IC handler with its exact
  # clamping: a negative start wraps from the end then floors at 0, and the
  # length is capped so start+len never exceeds size. The one-argument form
  # copies to the end; note len is computed from the ORIGINAL (pre-wrap)
  # start, matching the handler, so copy(-2) on a size-5 array copies the
  # last two elements.
  -> copy(start)
    copy(start, size - start)

  -> copy(start, count)
    n = $size ## i64
    s = start ## i64
    if s < 0
      s = n + s
    if s < 0
      s = 0
    len = count ## i64
    if len < 0
      len = 0
    if s + len > n
      len = n - s
    if len <= 0
      return []
    out = Array.new(len)
    i = 0
    while i < len
      out[i] = self[s + i]
      i += 1
    out

  # Deduplicate preserving `==` equality and first-occurrence order. Small
  # arrays (n <= 8) stay on the inline seen-scan (with 0/1/2-element fast
  # paths); larger arrays dispatch to `w_array_uniq`, which uses an O(n)
  # open-addressed hash index for hash-exact scalars and falls back to `w_eq`
  # for NaN, structural containers, and user instances.
  -> uniq
    n = $size ## i64
    if n == 0
      return []
    if n == 1
      return [self[0]]
    if n == 2
      a = self[0]
      b = self[1]
      return a == b ? [a] : [a, b]
    if n > 8
      return ccall("w_array_uniq", self)
    out = []
    i = 0
    while i < n
      value = self[i]
      seen = false
      m = out.size ## i64
      j = 0
      while j < m
        if out[j] == value
          seen = true
          j = m
        else
          j += 1
      if !seen
        out.push(value)
      i += 1
    out

  # Empty receiver yields [nil, nil], matching the former C handler.
  -> minmax
    n = $size ## i64
    if n == 0
      return [nil, nil]
    lo = self[0]
    hi = lo
    i = 1
    while i < n
      value = self[i]
      if value < lo
        lo = value
      elsif value > hi
        hi = value
      i += 1
    [lo, hi]

  # -- Counting sort (csort) — for integers over a bounded range --
  # O(n + range): scan for min/max, tally counts[value - min], then write the
  # values back in order. A large win when the range is tight relative to the
  # array size. Returns a new sorted array; falls back to the comparison sort
  # (Array#sort) for float/non-integer arrays or a range too sparse to be worth
  # the counts array.
  -> csort
    ccall("w_array_csort", self)

  # One argument: an Integer `count` means values live in [0, count); a Range
  # `a..b` gives an explicit [a, b]. (is_a?(Integer) picks the count form.)
  -> csort(a)
    if a.is_a?(Integer)
      ccall("w_array_csort_range", self, 0, a - 1)
    else
      ccall("w_array_csort_range", self, a.first, a.last)

  # Two arguments: explicit inclusive [min, max].
  -> csort(min, max)
    ccall("w_array_csort_range", self, min, max)

  # -- Explicit alternative sort algorithms (integer arrays) --
  # `sort` already picks the best of pdqsort/ipnsort/radix by element width,
  # size, and input pattern; these let you request a specific algorithm.
  # Float/generic arrays fall back to `sort`.
  #   tsort    — timsort: stable, adaptive (near-linear on already-sorted data)
  #   skasort  — in-place MSD byte-radix (american-flag sort)
  #   wolfsort — distribution + pdqsort hybrid
  #   ipnsort  — instruction-parallel network sort (Rust sort_unstable's algorithm)
  -> tsort
    ccall("w_array_tsort", self)
  -> skasort
    ccall("w_array_skasort", self)
  -> wolfsort
    ccall("w_array_wolfsort", self)
  -> ipnsort
    ccall("w_array_ipnsort", self)

  # Keep the separator overload before the zero-argument overload. Runtime
  # dispatch selects exact arity first and otherwise falls back to the first
  # method of this name, matching the former C handler's extra-argument
  # truncation. A default parameter is not equivalent: explicit nil must be
  # rejected, not replaced with the empty separator.
  -> join(separator)
    # Preserve the former C implementation's eager separator validation and
    # exact strlen boundary without copying into throwaway buffers.
    separator_length = ccall_nobox("w_stringy_c_length", separator) ## i64
    n = $size ## i64
    if n == 0
      return ""
    out = StringBuffer() ## recycle
    i = 0
    while i < n
      if i > 0 && separator_length > 0
        ccall("w_strbuf_append", out, separator)
      text = ccall("w_to_s", self[i])
      text_length = ccall_nobox("w_stringy_c_length", text) ## i64
      if text_length > 0
        ccall("w_strbuf_append", out, text)
      i += 1

    result = ccall("w_strbuf_to_s", out)
    # w_string_take returned a fresh heap string for a 6..61-byte result once
    # the static slab was frozen. StringBuffer#to_s can instead return the old
    # slab value; append it to an empty string to mint the exact fresh mode-7
    # representation in that one state.
    if ((result$value >> 1) & 7) == 6
      slab_frozen = ccall_nobox("w_slab_is_frozen") ## i64
      if slab_frozen == 1
        fresh = ""
        return fresh << result
    result

  -> join
    join("")

  # Concatenation: a new array of self's elements followed by @1's. The
  # `## T[n]` at call sites re-types the polymorphic result. Non-mutating.
  # The hypercomplex tower's Cayley–Dickson `*` joins its two halves here.
  -> concat/1
    if @1.is_a?(Array)
      n1 = $size ## i64
      n2 = @1.size ## i64
      total = n1 + n2
      if total == 0
        return []
      out = Array.new(total)
      i = 0
      while i < n1
        out[i] = self[i]
        i += 1
      j = 0
      while j < n2
        out[n1 + j] = @1[j]
        j += 1
      return out
    out = dup
    @1.each -> (x)
      out.push(x)
    out

  # Pythagorean (L2) norm: √(Σ xᵢ²). Naive form — overflow-safe for
  # the ML-scale ranges this is meant for; for bigger values use the
  # scaled algorithm in Math.hypot.
  -> pythagorean
    self/sq:sum.sqrt

  # Standard name for the L2 (Euclidean) norm — alias of pythagorean.
  -> norm
    pythagorean

  # Direction with magnitude 1: each element divided by the L2 norm.
  -> normalize
    self / pythagorean

  # Boxed → typed float buffer conversions (the %f32[…]/%f64[…] literals
  # desugar through these). Elements may be ints, decimals, or raw floats.
  -> to_f64
    ccall("w_array_to_f64", self)

  -> to_f32
    ccall("w_array_to_f32", self)

  -> data
    ccall("w_int", $slots ## i64)

  -> raw_ptr
    eb = ($ebits ## i64) & 0xFF
    if eb >= 128
      eb -= 256
    abs_bits = eb
    if eb == -116 || eb == 116
      abs_bits = 16
    elsif eb == -108 || eb == -109 || eb == 108
      abs_bits = 8
    elsif eb == -104
      abs_bits = 4
    elsif eb == 33
      abs_bits = 32
    elsif eb == 65 || eb == 66
      abs_bits = 64
    elsif eb < 0
      abs_bits = 0 - eb
    st = $start ## i64
    off = abs_bits == 4 ? (st / 2) : (st * (abs_bits / 8))
    ccall("w_int", (($slots ## i64) + off) ## i64)

  -> fill(value)
    ccall("w_array_fill", self, value)

  -> slice_view(start, length)
    ccall("w_array_view", self, start, length)

  -> cross(other)
    ccall("w_array_cross_float", self, other)

  -> scale(scalar)
    ccall("w_array_scale_float", self, scalar)

  -> scale!(scalar)
    ccall("w_array_scale_float_bang", self, scalar)

  -> matvec_i8(x, rows, cols)
    ccall("w_array_matvec_i8", self, x, rows, cols)

  -> matmul_i8(rhs, m, k, n)
    ccall("w_array_matmul_i8", self, rhs, m, k, n)

  # Arithmetic mean: Σxᵢ / n. Quantity elements fold from the first
  # element (there is no reverse-operand dispatch for 0 + quantity);
  # everything else rides the sum fast path.
  -> mean
    n = size
    if n == 0
      raise "mean of an empty array is undefined"
    x0 = self[0]
    if type(x0) == "Quantity"
      total = x0
      i = 1
      while i < n
        total += self[i]
        i += 1
      return total / n
    sum / n

  # Sample variance (Bessel-corrected: Σ(xᵢ−x̄)²/(n−1)), matching the
  # Ruby engine builtin. Folding from the first squared deviation keeps
  # Quantity elements on quantity arithmetic throughout — their variance
  # is a squared-unit quantity.
  -> variance
    n = size
    if n < 2
      raise "variance requires at least 2 values"
    m = mean
    d0 = self[0] - m
    acc = d0 * d0
    i = 1
    while i < n
      d = self[i] - m
      acc += d * d
      i += 1
    acc / (n - 1)

  # Sample standard deviation: √variance, matching the Ruby engine
  # builtin. Quantity elements convert to the first element's unit, σ is
  # computed on the bare values, and the unit re-attaches at the end —
  # √ of a squared-unit quantity has no runtime representation.
  -> stdev
    n = size
    if n < 2
      raise "stdev requires at least 2 values"
    x0 = self[0]
    nodigits = nil
    if type(x0) == "Quantity"
      uname = x0.unit_name
      vals = []
      i = 0
      while i < n
        q = ccall("w_quantity_pipe", self[i], uname, nodigits)
        vals.push(q.value)
        i += 1
      return ccall("w_quantity_pipe", vals.stdev, uname, nodigits)
    variance.sqrt

  # Middle value of the sorted elements; even sizes average the two
  # middles, matching the Ruby engine builtin.
  -> median
    n = size
    if n == 0
      raise "median of an empty array is undefined"
    sorted = sort
    if n % 2 == 1
      return sorted[n / 2]
    (sorted[n / 2 - 1] + sorted[n / 2]) / 2

  # Sorted copy. Blockless `sort` is ascending `<=>` order; a Ruby-style
  # comparator block (returning negative/zero/positive) picks the order.
  #
  # Dispatch note: on the compiled engine the WN_sort IC row intercepts
  # every `sort` call before this body — blockless calls ride the typed
  # qsort fast paths (w_array_sort), comparator calls ride the stable
  # bottom-up mergesort (w_array_sort_block). The interpreter mirrors the
  # blockless row natively and tree-walks this body for the comparator
  # form, so __mergesort_copy below must stay in lockstep with
  # w_array_sort_block. (The Ruby engine has its own builtin twins.)
  -> sort(&)
    if block?
      self.__mergesort_copy -> (a, b)
        &(a, b)
    else
      ccall("w_array_stable_sort", self)

  # In-place counterparts: sort into a copy through the same machinery,
  # then write the ordered elements back through `[]=` (preserves the
  # receiver's identity and typed storage). The `array_mergesort!` extern
  # these used to call only ever existed as a Ruby-engine builtin — on
  # the other two engines it was an undefined method since inception.
  -> sort!
    self.__replace_elements(self.sort)

  -> sort!(&)
    sorted = self.sort -> (a, b)
      &(a, b)
    self.__replace_elements(sorted)

  # Stable sorted copy: elements that compare equal keep their input
  # order. Typed and homogeneous arrays ride the same width-tuned kernels
  # as `sort` (equal values there are indistinguishable, and the radix
  # tiers are stable by construction); mixed polymorphic arrays — the one
  # blockless case where stability is observable, e.g. 2 vs 2.0 — use a
  # stable bottom-up mergesort where `sort` uses an unstable qsort. The
  # comparator-block form mirrors `sort`'s, which is stable on every path.
  #
  # Dispatch note: like `sort`, the compiled engine intercepts every call
  # through the WN_stable_sort IC row (blockless → w_array_stable_sort,
  # block → w_array_sort_block) — this body runs on the interpreter only.
  -> stable_sort
    ccall("w_array_stable_sort", self)

  -> stable_sort(&)
    if block?
      self.__mergesort_copy -> (a, b)
        &(a, b)
    else
      ccall("w_array_stable_sort", self)

  # Stable in-place sort. Uses `<=>` by default and accepts a Ruby-style
  # comparator block returning negative/zero/positive. Unlike blockless
  # `sort!` (whose compiled fast path is an unstable qsort), this
  # spelling guarantees stability on every path.
  -> mergesort!
    self.__replace_elements(ccall("w_array_stable_sort", self))

  -> mergesort!(&)
    sorted = self.__mergesort_copy -> (a, b)
      &(a, b)
    self.__replace_elements(sorted)

  # Stable bottom-up merge sort returning a fresh polymorphic Array,
  # ordered by the required comparator block. Tree-walked twin of the
  # runtime's w_array_sort_block and the Ruby engine's
  # Runtime::Builtins.array_mergesort_copy.
  -> __mergesort_copy(&)
    n = size
    src = dup
    if n < 2
      return src
    dst = Array.new(n)
    width = 1
    while width < n
      left = 0
      while left < n
        mid = left + width
        if mid > n
          mid = n
        right = left + width * 2
        if right > n
          right = n
        i = left
        j = mid
        k = left
        while i < mid && j < right
          vi = src[i]
          vj = src[j]
          if &(vi, vj) <= 0
            dst[k] = vi
            i += 1
          else
            dst[k] = vj
            j += 1
          k += 1
        while i < mid
          dst[k] = src[i]
          i += 1
          k += 1
        while j < right
          dst[k] = src[j]
          j += 1
          k += 1
        left += width * 2
      swap = src
      src = dst
      dst = swap
      width *= 2
    src

  # Overwrite self element-by-element from `other` (same length assumed;
  # used by the in-place sorts, whose copies preserve the length).
  -> __replace_elements(other)
    n = $size ## i64
    i = 0
    while i < n
      self[i] = other[i]
      i += 1
    self

  # Random shuffle. Called with no argument this returns a fresh randomly
  # ordered copy through the runtime's secure unbiased Fisher-Yates
  # (w_array_shuffle) — typed receivers shuffle into typed results. Passing a
  # leading Array of indexes keeps the existing indexed-gather overload
  # (gathers those positions in order).
  #
  # Two bugs once blocked this on the compiled and self-hosted engines: the
  # body called a Ruby-only `array_shuffle` extern, and parameter splats were
  # not packed. Parameter splats are now supported; the plain optional `sel`
  # remains the actual API because the runtime has no seeded/custom RNG option.
  # On the Ruby engine this source is shadowed by that engine's own `shuffle`
  # builtin, so the ccall never runs there.
  #
  # No seeding: the `random:` custom-RNG option the Ruby engine accepts is not
  # honored here — there is no seeded RNG in the runtime, so consumers needing
  # reproducibility build their own (e.g. koala's Splitter LCG). A non-Array
  # argument (such as an options Hash) is treated as the random path.
  -> shuffle(sel = nil)
    if sel != nil && sel.is_a?(Array)
      sel.map -> (idx)
        self[idx]
    else
      ccall("w_array_shuffle", self)

  # In-place shuffle: permute a fresh copy through the same secure machinery,
  # then write the elements back through `[]=` (preserves the receiver's
  # identity and typed storage, like sort!). Returns self.
  -> shuffle!
    self.__replace_elements(self.shuffle)

  # Return a copy with elements rotated left by `count` (Ruby Array#rotate):
  # [1,2,3,4].rotate -> [2,3,4,1], rotate(2) -> [3,4,1,2], rotate(-1) ->
  # [4,1,2,3]. Pure Tungsten (the former `array_rotate` intrinsic does not
  # exist). `%` is C-style here, so normalize a negative offset into [0, n).
  -> rotate(count = 1)
    ro_n = $size ## i64
    if ro_n == 0
      return []
    ro_k = (count ## i64) % ro_n
    if ro_k < 0
      ro_k = ro_k + ro_n
    ro_out = Array.new(ro_n)
    ro_tail = ro_n - ro_k
    ro_i = 0
    while ro_i < ro_tail
      ro_out[ro_i] = self[ro_k + ro_i]
      ro_i += 1
    ro_j = 0
    while ro_j < ro_k
      ro_out[ro_tail + ro_j] = self[ro_j]
      ro_j += 1
    ro_out

  # In-place rotate: three-reversal algorithm in-place, zero allocation.
  -> rotate!(count = 1)
    ro_n = $size ## i64
    if ro_n <= 1
      return self
    ro_k = (count ## i64) % ro_n
    if ro_k < 0
      ro_k = ro_k + ro_n
    if ro_k == 0
      return self
    lo = 0
    hi = ro_k - 1
    while lo < hi
      tmp = self[lo]
      self[lo] = self[hi]
      self[hi] = tmp
      lo += 1
      hi -= 1
    lo = ro_k
    hi = ro_n - 1
    while lo < hi
      tmp = self[lo]
      self[lo] = self[hi]
      self[hi] = tmp
      lo += 1
      hi -= 1
    lo = 0
    hi = ro_n - 1
    while lo < hi
      tmp = self[lo]
      self[lo] = self[hi]
      self[hi] = tmp
      lo += 1
      hi -= 1
    self

  -> __flatten_into(out, depth)
    fl_n = $size ## i64
    fl_i = 0
    if depth == 0
      while fl_i < fl_n
        out.push(self[fl_i])
        fl_i += 1
      return out
    next_depth = depth < 0 ? -1 : depth - 1
    while fl_i < fl_n
      fl_x = self[fl_i]
      if fl_x.is_a?(Array)
        fl_x.__flatten_into(out, next_depth)
      else
        out.push(fl_x)
      fl_i += 1
    out

  # Recursively flatten nested arrays into a single flat array. Each element
  # that is itself an Array is expanded (at every depth); non-Array elements
  # pass through. Returns a new array; the receiver is untouched.
  -> flatten
    __flatten_into([], -1)

  # Flatten only `depth` levels of nesting (Ruby-style). depth <= 0 is a
  # shallow copy; each level peels one layer of Array nesting.
  -> flatten(depth)
    if depth <= 0
      return dup
    __flatten_into([], depth)

  # Transpose a rectangular array of rows (array of equal-length arrays):
  # result[c][r] == self[r][c]. Empty receiver returns []. Assumes rows are
  # equal length (uses the first row's width), matching typical matrix/table
  # use.
  -> transpose
    tr_rows = $size ## i64
    if tr_rows == 0
      return []
    tr_cols = self[0].size ## i64
    if tr_cols == 0
      return []
    tr_out = Array.new(tr_cols)
    tr_c = 0
    while tr_c < tr_cols
      tr_out[tr_c] = Array.new(tr_rows)
      tr_c += 1
    tr_r = 0
    while tr_r < tr_rows
      row = self[tr_r]
      tr_c = 0
      while tr_c < tr_cols
        tr_out[tr_c][tr_r] = row[tr_c]
        tr_c += 1
      tr_r += 1
    tr_out

  # Split into runs of consecutive elements: a new chunk begins whenever the
  # block returns false for an adjacent (previous, current) pair (Ruby
  # Enumerable#chunk_while). e.g. [1,2,4,5,7].chunk_while -> (a, b) b - a == 1
  # => [[1,2],[4,5],[7]]. Uses the anonymous `&` form so it also runs under
  # the interpreter.
  -> chunk_while(&)
    cw_n = size
    if cw_n == 0
      return []
    cw_out = []
    cw_cur = [self[0]]
    cw_i = 1
    while cw_i < cw_n
      cw_v = self[cw_i]
      if &(self[cw_i - 1], cw_v)
        cw_cur.push(cw_v)
      else
        cw_out.push(cw_cur)
        cw_cur = [cw_v]
      cw_i += 1
    cw_out.push(cw_cur)
    cw_out
