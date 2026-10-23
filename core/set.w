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
  -> new
    @storage = {}

  -> new(elements)
    @storage = {}
    elements.each -> (element)
      @storage[element] = true

  -> new(@storage, trusted)

  -> .of(elements)
    Set.new(elements)
  -> .empty
    Set.new
  -> .from_array(array)
    Set.new(array)

  # ---- accessors ----
  ro :storage
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
    out = {}
    @storage.each -> (element, _)
      out[element] = true
    other.storage.each -> (element, _)
      out[element] = true
    Set.new(out, true)
  -> intersect(other)
    out = {}
    other_s = other.storage
    @storage.each -> (element, _)
      if other_s.has_key?(element)
        out[element] = true
    Set.new(out, true)
  -> diff(other)
    out = {}
    other_s = other.storage
    @storage.each -> (element, _)
      if !other_s.has_key?(element)
        out[element] = true
    Set.new(out, true)
  -> symmetric_diff(other)
    out = {}
    other_s = other.storage
    @storage.each -> (element, _)
      if !other_s.has_key?(element)
        out[element] = true
    other_s.each -> (element, _)
      if !@storage.has_key?(element)
        out[element] = true
    Set.new(out, true)

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
    return false if self.size > other.size
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
    return true if self.empty? || other.empty?
    elements = self.to_a
    i = 0
    while i < elements.size
      return false if other.include?(elements[i])
      i += 1
    true

  # ---- mutation (returns new Set; sets are immutable values) ----
  -> add(element)
    return self if @storage.has_key?(element)
    storage = {}
    @storage.each -> (k, _)
      storage[k] = true
    storage[element] = true
    Set.new(storage, true)
  -> remove(element)
    return self if !@storage.has_key?(element)
    storage = {}
    @storage.each -> (k, _)
      if k != element
        storage[k] = true
    Set.new(storage, true)

  # ---- conversion ----
  -> to_a
    @storage.keys
  -> to_array
    self.to_a
  -> to_multiset

  -> each(&)
    keys = @storage.keys
    i = 0
    while i < keys.size
      &(keys[i])
      i += 1
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
    h = 0
    @storage.each -> (element, _)
      h = h ^ element.hash
    h

  -> to_s
    elements = self.to_a.to_s
    "{" + elements.slice(1, elements.size - 2) + "}"
  -> inspect
    self.to_s
