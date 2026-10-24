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

use core/set

+ Multiset
  is Enumerable

  # ---- construction ----
  -> new
    @counts = {}
    @total_size = 0

  -> new(elements)
    @counts = {}
    @total_size = 0
    t = type(elements)
    if t == "Array"
      n = elements.size
      i = 0
      while i < n
        el = elements[i]
        c = @counts[el]
        if c == nil
          @counts[el] = 1
        else
          @counts[el] = c + 1
        @total_size += 1
        i += 1
    elsif t == "Hash"
      ks = elements.keys
      vs = elements.values
      n = ks.size
      i = 0
      while i < n
        c = vs[i]
        if c > 0
          @counts[ks[i]] = c
          @total_size += c
        i += 1
    elsif elements.is_a?(Multiset)
      raw = elements.raw_counts
      ks = raw.keys
      vs = raw.values
      n = ks.size
      i = 0
      while i < n
        @counts[ks[i]] = vs[i]
        @total_size += vs[i]
        i += 1
    else
      elements.each -> (el)
        c = @counts[el]
        if c == nil
          @counts[el] = 1
        else
          @counts[el] = c + 1
        @total_size += 1

  -> new(@counts, @total_size, trusted)

  -> .of(elements)
    Multiset.new(elements)

  -> .empty
    Multiset.new

  -> .from_array(array)
    Multiset.new(array)

  -> .from_counts(hash)
    Multiset.new(hash)

  # ---- accessors ----
  -> raw_counts
    @counts

  -> size
    @total_size

  -> length
    @total_size

  -> empty?
    @total_size == 0

  -> count(element)
    c = @counts[element]
    if c == nil
      return 0
    c

  -> counts
    @counts.dup

  -> support
    out = {}
    ks = @counts.keys
    n = ks.size
    i = 0
    while i < n
      out[ks[i]] = true
      i += 1
    Set.new(out, true)

  -> uniq
    self.support

  -> distinct_count
    @counts.size

  # ---- iteration: each yields every occurrence (duplicates included) ----
  -> each(&)
    ks = @counts.keys
    vs = @counts.values
    n = ks.size
    i = 0
    while i < n
      el = ks[i]
      c = vs[i]
      j = 0
      while j < c
        &(el)
        j += 1
      i += 1
    self

  -> each_unique(&)
    ks = @counts.keys
    n = ks.size
    i = 0
    while i < n
      &(ks[i])
      i += 1
    self

  -> each_with_count(&)
    ks = @counts.keys
    vs = @counts.values
    n = ks.size
    i = 0
    while i < n
      &(ks[i], vs[i])
      i += 1
    self

  # ---- membership ----
  -> include?(element)
    @counts.has_key?(element)

  # ---- multiset arithmetic ----
  -> union(other)
    out = @counts.dup
    total = @total_size
    other_c = other.raw_counts
    ks = other_c.keys
    vs = other_c.values
    n = ks.size
    i = 0
    while i < n
      k = ks[i]
      v = vs[i]
      cur = out[k]
      if cur == nil
        out[k] = v
      else
        out[k] = cur + v
      total += v
      i += 1
    Multiset.new(out, total, true)

  -> intersect(other)
    out = {}
    total = 0
    other_c = other.raw_counts
    ks = @counts.keys
    vs = @counts.values
    n = ks.size
    i = 0
    while i < n
      k = ks[i]
      oc = other_c[k]
      if oc != nil
        sc = vs[i]
        m = sc < oc ? sc : oc
        if m > 0
          out[k] = m
          total += m
      i += 1
    Multiset.new(out, total, true)

  -> diff(other)
    out = {}
    total = 0
    other_c = other.raw_counts
    ks = @counts.keys
    vs = @counts.values
    n = ks.size
    i = 0
    while i < n
      k = ks[i]
      sc = vs[i]
      oc = other_c[k]
      rem = oc == nil ? sc : sc - oc
      if rem > 0
        out[k] = rem
        total += rem
      i += 1
    Multiset.new(out, total, true)

  -> |(other)
    self.union(other)

  -> &(other)
    self.intersect(other)

  -> -(other)
    self.diff(other)

  # ---- conversion ----
  -> to_a
    out = Array.new(@total_size)
    ks = @counts.keys
    vs = @counts.values
    n = ks.size
    pos = 0
    i = 0
    while i < n
      el = ks[i]
      c = vs[i]
      j = 0
      while j < c
        out[pos] = el
        pos += 1
        j += 1
      i += 1
    out

  -> to_set
    self.support

  -> to_hash
    self.counts

  # ---- comparison ----
  -> ==(other)
    return false if !other.is_a?(Multiset)
    return false if @total_size != other.size
    other_c = other.raw_counts
    return false if @counts.size != other_c.size
    ks = @counts.keys
    vs = @counts.values
    n = ks.size
    i = 0
    while i < n
      if other_c[ks[i]] != vs[i]
        return false
      i += 1
    true

  -> hash
    h = 0
    ks = @counts.keys
    vs = @counts.values
    n = ks.size
    i = 0
    while i < n
      h = h ^ (ks[i].hash * 31 + vs[i].hash)
      i += 1
    h

  -> to_s
    arr = self.to_a
    if arr.size == 0
      return "<{}>"
    "<{ " + arr.join(", ") + " }>"

  -> inspect
    self.to_s
