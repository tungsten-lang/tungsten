# Set — mathematical set: unique elements, unordered, O(1) membership.
#
# Source syntax: `{1, 2, 3}` (distinct from hash `{a: 1}` and block `{x}`).
# The parser uses comma-separator presence to disambiguate from hash literals.
#
# Element-level equality uses each element's `==`. Sets containing literals
# that mix in BitEqual benefit from O(1) hash + comparison automatically.
+ Set
  is Enumerable
  is Comparable

  - data
    storage hash       # element → true; the value column is always true
    cached_hash i64    # memoized identity hash (lazy)

  # ---- construction ----
  -> parse(string)
  -> of(elements)
  -> empty
  -> from_array(array)

  # ---- accessors ----
  -> size
  -> length
    self.size
  -> empty?
    self.size == 0

  # ---- membership ----
  -> include?(element)
  -> member?(element)
    self.include?(element)

  # ---- set arithmetic ----
  # Operator forms route to the Tungsten-flavored `union` / `intersect` / `diff`.
  -> union(other)
  -> intersect(other)
  -> diff(other)
  -> symmetric_diff(other)

  # Operator forms (`a | b`, `a & b`, `a - b`, `a ^ b`) route to the named
  # methods above. Wired up at the runtime level.

  # ---- relations ----
  -> subset?(other)
  -> superset?(other)
  -> proper_subset?(other)
  -> proper_superset?(other)
  -> disjoint?(other)
    self.intersect(other).empty?

  # ---- mutation (returns new Set; sets are immutable values) ----
  -> add(element)
  -> remove(element)

  # ---- conversion ----
  -> to_a
  -> to_array
    self.to_a
  -> to_multiset

  # ---- comparison: subset gives a partial order ----
  -> <=>(other)
    if self == other
      0
    elsif self.proper_subset?(other)
      -1
    elsif self.proper_superset?(other)
      1
    else
      nil

  -> ==(other)
    other is Set && self.size == other.size && self.subset?(other)

  -> hash

  -> to_s
  -> inspect
    self.to_s
