# Multiset (a.k.a. bag) — elements with multiplicities.
#
# Source syntax: `<{1, 2, 2, 3}>`. Distinct from Set in that duplicates are
# preserved as counts. Set arithmetic preserves multiplicity:
#
#   union (|)         — counts add:           <{a: 2}> | <{a: 3}> = <{a: 5}>
#   intersect (&)     — counts take the min:  <{a: 2}> & <{a: 3}> = <{a: 2}>
#   diff (-)          — counts subtract:      <{a: 5}> - <{a: 3}> = <{a: 2}>
#
# Useful for prime factorizations, cardinality-aware tag counting, and any
# context where "how many" matters as much as "which".
+ Multiset
  is Enumerable

  - data
    counts hash         # element → integer count (>= 1)

  # ---- construction ----
  -> of(elements)         # accepts Array, Multiset, Hash[element → count]
  -> empty
  -> from_array(array)    # tally an Array into a Multiset
  -> from_counts(hash)    # Hash{element → count} → Multiset

  # ---- accessors ----
  -> size                 # total count, including duplicates
  -> length
    self.size
  -> empty?
    self.size == 0
  -> count(element)       # multiplicity of a specific element (0 if absent)
  -> counts               # Hash{element → count}, defensive copy
  -> support              # Set of distinct elements (alias: uniq)

  -> uniq
    self.support
  -> distinct_count
    self.support.size

  # ---- iteration: each yields every occurrence (duplicates included) ----
  -> each(block)
  -> each_unique(block)   # yields each distinct element once
  -> each_with_count(block)  # yields (element, count) pairs

  # ---- membership ----
  -> include?(element)
    self.count(element) > 0

  # ---- multiset arithmetic ----
  -> union(other)         # additive: counts add
  -> intersect(other)     # min: counts take the lesser
  -> diff(other)          # subtractive: counts subtract, floor at 0

  # Operator forms (`a | b`, `a & b`, `a - b`) route to the named methods
  # above. Wired up at the runtime level.

  # ---- conversion ----
  -> to_a                  # Array with duplicates expanded
  -> to_set                # cast to Set (drops counts)
  -> to_hash               # alias for counts

  # ---- comparison ----
  -> ==(other)
  -> hash

  -> to_s                  # "<{ 1, 2, 2, 3 }>"
  -> inspect
    self.to_s
