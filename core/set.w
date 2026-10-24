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
    s = {}
    if type(elements) == "Array"
      n = elements.size
      i = 0
      while i < n
        s[elements[i]] = true
        i += 1
    else
      elements.each -> (element)
        s[element] = true
    @storage = s

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
    out.merge!(@storage)
    out.merge!(other.storage)
    Set.new(out, true)
  -> intersect(other)
    out = {}
    s = @storage ## hash
    other_s = other.storage ## hash
    if s.size <= other_s.size
      elements = s.keys
      n = elements.size
      i = 0
      while i < n
        el = elements[i]
        if other_s.has_key?(el)
          out[el] = true
        i += 1
    else
      elements = other_s.keys
      n = elements.size
      i = 0
      while i < n
        el = elements[i]
        if s.has_key?(el)
          out[el] = true
        i += 1
    Set.new(out, true)
  -> diff(other)
    out = {}
    s = @storage ## hash
    other_s = other.storage ## hash
    elements = s.keys
    n = elements.size
    i = 0
    while i < n
      el = elements[i]
      if !other_s.has_key?(el)
        out[el] = true
      i += 1
    Set.new(out, true)
  -> symmetric_diff(other)
    out = {}
    s = @storage ## hash
    other_s = other.storage ## hash
    elements = s.keys
    n = elements.size
    i = 0
    while i < n
      el = elements[i]
      if !other_s.has_key?(el)
        out[el] = true
      i += 1
    other_elements = other_s.keys
    m = other_elements.size
    j = 0
    while j < m
      el = other_elements[j]
      if !s.has_key?(el)
        out[el] = true
      j += 1
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
    s = @storage ## hash
    other_s = other.storage ## hash
    elements = s.keys
    n = elements.size
    i = 0
    while i < n
      return false if !other_s.has_key?(elements[i])
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
    if self.size > other.size
      return other.disjoint?(self)
    s = @storage ## hash
    other_s = other.storage ## hash
    elements = s.keys
    n = elements.size
    i = 0
    while i < n
      return false if other_s.has_key?(elements[i])
      i += 1
    true

  # ---- mutation (returns new Set; sets are immutable values) ----
  -> add(element)
    s = @storage ## hash
    return self if s.has_key?(element)
    storage = {}
    storage.merge!(s)
    storage[element] = true
    Set.new(storage, true)
  -> remove(element)
    s = @storage ## hash
    return self if !s.has_key?(element)
    storage = {}
    storage.merge!(s)
    storage.delete(element)
    Set.new(storage, true)

  # ---- conversion ----
  -> to_a
    @storage.keys
  -> to_array
    self.to_a
  -> to_multiset
    Multiset.from_array(self.to_a)

  -> each(&)
    @storage.each -> (k, _)
      &(k)
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
