# Set — mathematical set: unique elements, unordered, O(1) membership.
#
# Construct with Set.of([1, 2, 3]); {} remains an empty hash.
#
# Element-level equality uses each element's `==`. Sets containing literals
# that mix in BitEqual benefit from O(1) hash + comparison automatically.
+ Set
  is Enumerable
  is Comparable

  # ---- construction ----
  -> new(elements = [])
    @storage = {}
    elements.each -> (element)
      @storage[element] = true

  -> .of(elements)
    Set.new(elements)
  -> .empty
    Set.new
  -> .from_array(array)
    Set.new(array)

  # ---- accessors ----
  -> size
    @storage.size
  -> length
    self.size
  -> empty?
    self.size == 0

  # ---- membership ----
  -> include?(element)
    @storage.has_key?(element)
  -> member?(element)
    self.include?(element)

  # ---- set arithmetic ----
  # Operator forms route to the Tungsten-flavored `union` / `intersect` / `diff`.
  -> union(other)
    Set.new(self.to_a + other.to_a)
  -> intersect(other)
    result = []
    self.to_a.each -> (element)
      result.push(element) if other.include?(element)
    Set.new(result)
  -> diff(other)
    result = []
    self.to_a.each -> (element)
      result.push(element) if !other.include?(element)
    Set.new(result)
  -> symmetric_diff(other)
    self.diff(other).union(other.diff(self))

  # Operator forms (`a | b`, `a & b`, `a - b`, `a ^ b`) route to the named
  # methods above.
  -> |(other)
    self.union(other)
  -> &(other)
    self.intersect(other)
  -> -(other)
    self.diff(other)
  -> ^(other)
    self.symmetric_diff(other)

  # ---- relations ----
  -> subset?(other)
    elements = self.to_a
    i = 0
    while i < elements.size
      return false if !other.include?(elements[i])
      i += 1
    true
  -> superset?(other)
    other.subset?(self)
  -> proper_subset?(other)
    self.size < other.size && self.subset?(other)
  -> proper_superset?(other)
    other.proper_subset?(self)
  -> disjoint?(other)
    self.intersect(other).empty?

  # ---- mutation (returns new Set; sets are immutable values) ----
  -> add(element)
    Set.new(self.to_a + [element])
  -> remove(element)
    self.diff(Set.new([element]))

  # ---- conversion ----
  -> to_a
    @storage.keys
  -> to_array
    self.to_a
  -> to_multiset

  -> each(&)
    self.to_a.each -> (element)
      &(element)
    self

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
    other.is_a?(Set) && self.size == other.size && self.subset?(other)

  -> hash
    self.to_a.reduce(0) -> (acc, element) acc ^ element.hash

  -> to_s
    elements = self.to_a.to_s
    "{" + elements.slice(1, elements.size - 2) + "}"
  -> inspect
    self.to_s
