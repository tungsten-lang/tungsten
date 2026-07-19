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
    i = 0
    n = self.size
    while i < n
      out.push(self[i])
      i++
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
    out = []
    n = $size ## i64
    i = 0
    while i < n
      value = self[i]
      if value != nil
        out.push(value)
      i += 1
    out

  -> dup
    out = []
    n = $size ## i64
    i = 0
    while i < n
      out.push(self[i])
      i += 1
    out

  # take/drop are ports of the former runtime IC handlers (Phase 7+j),
  # keeping their exact clamping semantics (negative counts clamp to 0,
  # oversized counts to $size). Like compact/dup they return ordinary
  # polymorphic Arrays for typed and view receivers. Benchmarked at parity
  # with the retired C handlers; see benchmarks/builtins/.
  -> take(count)
    out = []
    n = $size ## i64
    n = count if count < n
    i = 0
    while i < n
      out.push(self[i])
      i += 1
    out

  -> drop(count)
    out = []
    n = $size ## i64
    i = count ## i64
    if i < 0
      i = 0
    while i < n
      out.push(self[i])
      i += 1
    out

  -> reverse
    out = []
    n = $size ## i64
    i = n - 1
    while i >= 0
      out.push(self[i])
      i -= 1
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
    while i < n - 1
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
    out = []
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
    stop = s + len
    i = s
    while i < stop
      out.push(self[i])
      i += 1
    out

  # Quadratic seen-scan over the result, matching the former C handler: `==`
  # equality, first occurrence wins. A hash-set would change which values
  # collapse together (hash-key equality), so this stays faithful.
  -> uniq
    out = []
    n = $size ## i64
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
      lo = value if value < lo
      hi = value if value > hi
      i += 1
    [lo, hi]

  # Keep the separator overload before the zero-argument overload. Runtime
  # dispatch selects exact arity first and otherwise falls back to the first
  # method of this name, matching the former C handler's extra-argument
  # truncation. A default parameter is not equivalent: explicit nil must be
  # rejected, not replaced with the empty separator.
  -> join(separator)
    # Preserve the former C implementation's eager separator validation and
    # exact strlen boundary without copying into throwaway buffers.
    separator_length = ccall_nobox("w_stringy_c_length", separator) ## i64

    # The first live-size pass validates every raw to_s result. Lengths remain
    # deliberately unused: exact preallocation was slower than default growth.
    i = 0
    while i < $size
      text = ccall("w_to_s", self[i])
      text_length = ccall_nobox("w_stringy_c_length", text) ## i64
      i += 1

    # Allocate only the returned output buffer, after validation has finished.
    out = StringBuffer() ## recycle
    i = 0
    while i < $size
      if i > 0
        ccall("w_strbuf_append", out, separator)
      text = ccall("w_to_s", self[i])
      ccall("w_strbuf_append", out, text)
      i += 1

    result = ccall("w_strbuf_to_s", out)
    # w_string_take returned a fresh heap string for a 6..61-byte result once
    # the static slab was frozen. StringBuffer#to_s can instead return the old
    # slab value; append it to an empty string to mint the exact fresh mode-7
    # representation in that one state.
    if ((wvalue_bits(result) >> 1) & 7) == 6
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
    out = []
    self.each -> (x)
      out.push(x)
    @1.each -> (x)
      out.push(x)
    out

  # Pythagorean (L2) norm: √(Σ xᵢ²). Naive form — overflow-safe for
  # the ML-scale ranges this is meant for; for bigger values use the
  # scaled algorithm in Math.hypot.
  -> pythagorean
    self/sq:sum.sqrt

  # Direction with magnitude 1: each element divided by the L2 norm.
  -> normalize
    self / pythagorean

  -> sort(&)
    if block_given?
      array_mergesort(self) -> (a, b)
        &(a, b)
    else
      array_mergesort(self)

  -> sort!
    mergesort!

  -> sort!(&)
    mergesort! -> (a, b)
      &(a, b)

  # Stable in-place sort. Uses `<=>` by default and accepts a Ruby-style
  # comparator block returning negative/zero/positive.
  -> mergesort!
    array_mergesort!(self)

  -> mergesort!(&)
    array_mergesort!(self) -> (a, b)
      &(a, b)

  # Random shuffle when called with no positional index list, preserving the
  # existing indexed-gather overload below. `random:` may be any object with
  # `rand(limit)` or `random_number(limit)`.
  -> shuffle(*args)
    if args.size > 0 && !args[0].is_a?(Hash)
      args[0].map -> self[item]
    else
      array_shuffle(self, *args)

  -> shuffle!(*opts)
    array_shuffle!(self, *opts)

  # Return a copy with elements rotated left by `count` (Ruby Array#rotate):
  # [1,2,3,4].rotate -> [2,3,4,1], rotate(2) -> [3,4,1,2], rotate(-1) ->
  # [4,1,2,3]. Pure Tungsten (the former `array_rotate` intrinsic does not
  # exist). `%` is C-style here, so normalize a negative offset into [0, n).
  -> rotate(count = 1)
    ro_n = size
    if ro_n == 0
      return []
    ro_k = count % ro_n
    if ro_k < 0
      ro_k = ro_k + ro_n
    ro_out = []
    ro_i = 0
    while ro_i < ro_n
      ro_out.push(self[(ro_i + ro_k) % ro_n])
      ro_i += 1
    ro_out

  # In-place rotate: overwrite self with the rotated order and return self.
  -> rotate!(count = 1)
    ro_r = rotate(count)
    ro_j = 0
    while ro_j < size
      self[ro_j] = ro_r[ro_j]
      ro_j += 1
    self

  # Recursively flatten nested arrays into a single flat array. Each element
  # that is itself an Array is expanded (at every depth); non-Array elements
  # pass through. Returns a new array; the receiver is untouched.
  -> flatten
    out = []
    self.each -> (x)
      if x.is_a?(Array)
        x.flatten.each -> (y)
          out.push(y)
      else
        out.push(x)
    out

  # Flatten only `depth` levels of nesting (Ruby-style). depth <= 0 is a
  # shallow copy; each level peels one layer of Array nesting.
  -> flatten(depth)
    if depth <= 0
      return dup
    out = []
    self.each -> (x)
      if x.is_a?(Array)
        x.flatten(depth - 1).each -> (y)
          out.push(y)
      else
        out.push(x)
    out

  # Transpose a rectangular array of rows (array of equal-length arrays):
  # result[c][r] == self[r][c]. Empty receiver returns []. Assumes rows are
  # equal length (uses the first row's width), matching typical matrix/table
  # use.
  -> transpose
    if size == 0
      return []
    tr_cols = self[0].size
    tr_out = []
    tr_c = 0
    while tr_c < tr_cols
      tr_row = []
      self.each -> (r)
        tr_row.push(r[tr_c])
      tr_out.push(tr_row)
      tr_c += 1
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
      if &(self[cw_i - 1], self[cw_i])
        cw_cur.push(self[cw_i])
      else
        cw_out.push(cw_cur)
        cw_cur = [self[cw_i]]
      cw_i += 1
    cw_out.push(cw_cur)
    cw_out
