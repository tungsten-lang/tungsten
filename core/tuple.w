# Tuple — a heterogeneous, fixed, dynamically-indexable value grouping.
#
# Backed by a poly array (each slot a boxed value), so elements may be of any
# class — the *representation* is uniform (one boxed WValue per slot) while the
# *classes* vary. That's what lets `t[i]` work with a runtime index while still
# holding mixed types. Use it for multi-return, argument bundles, composite keys,
# and grouping.
#
# Pick the right aggregate:
#   - homogeneous unboxed numbers  → i32[] / f64[] / SmallArray<T> (raw, fast)
#   - heterogeneous, indexed by runtime i → Tuple (this: boxed poly slots)
#   - heterogeneous raw record indexed by CONSTANT position (e.g. call frames)
#     → a monomorphized typed signature, not a stdlib type
+ Tuple
  is Enumerable

  -> new(@items)
    self

  # Convenience: Tuple.of([...]) reads clearer than Tuple.new at call sites.
  -> .of(items)
    Tuple.new(items)

  -> items
    @items

  # Index-based iteration: mode 1 lets map/select use [] + size directly; the
  # single-yield `each` below backs the combinators that go through
  # __enumerable_each (sum, reduce, to_a via the trait, ...).
  -> __enumerable_iteration_mode
    1

  -> each(&block)
    i = 0
    n = @items.size
    while i < n
      block(@items[i])
      i += 1
    self

  -> [](i)
    @items[i]

  -> size
    @items.size

  -> length
    @items.size

  -> empty?
    @items.size == 0

  -> first
    @items[0]

  -> last
    @items[@items.size - 1]

  -> to_a
    @items

  -> to_array
    @items

  # Structural equality, element-wise. Works against any receiver exposing
  # `size` + `[]`. `==` and `eql?` are the same check (w_eq now dispatches the
  # operator to a user-defined `==`).
  -> ==/1
    self.eql?(@1)

  -> eql?(other)
    if other.size != self.size
      return false
    i = 0
    while i < self.size
      if self[i] != other[i]
        return false
      i += 1
    true

  -> to_s
    "(" + @items.join(", ") + ")"
