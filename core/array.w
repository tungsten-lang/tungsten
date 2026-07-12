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

  -> rotate(count = 1)
    array_rotate(self, count)

  -> rotate!(count = 1)
    array_rotate!(self, count)
