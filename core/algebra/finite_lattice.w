# Finite lattices and Knaster-Tarski fixpoints.
#
# A FiniteLattice is a finite set of elements with a partial order in which
# every pair has a meet (greatest lower bound) and a join (least upper
# bound); finiteness then gives a bottom and a top. The constructor takes
# the carrier and a callable leq(a, b) for the order, verifies the poset
# axioms and the existence of all meets and joins, and precomputes the
# meet/join tables — construction is O(n^3) in the number of elements, so
# this is a tool for small, explicit lattices.
#
# For a monotone f : L -> L, Knaster-Tarski says the fixpoints of f form a
# complete lattice; in particular least and greatest fixpoints exist, and
#
#   lfp f = meet { x | f(x) <= x }   (the prefixpoints)
#   gfp f = join { x | x <= f(x) }   (the postfixpoints)
#
# Finiteness makes them computable by Kleene iteration: the chain
# bottom <= f(bottom) <= f(f(bottom)) <= ... stabilizes at lfp f within
# height(L) steps, and dually from the top for gfp f. least_fixpoint and
# greatest_fixpoint check monotonicity before iterating, so a non-monotone
# argument raises instead of looping or returning a junk value.

+ FiniteLattice
  -> new(elements, leq)
    @elements = []
    elements.each ->(e)
      @elements.push(e)
    raise "a lattice needs at least one element" if @elements.size == 0
    @leq = leq
    build_order!
    build_tables!

  # --- standard lattices ---

  # The chain 0 < 1 < ... < n-1.
  -> .chain(n)
    raise "a chain needs at least one element" if n < 1
    values = []
    i = 0
    while i < n
      values.push(i)
      i += 1
    FiniteLattice.new(values, ->(a, b) a <= b)

  # Divisors of n ordered by divisibility: meet is gcd, join is lcm.
  -> .divisors(n)
    raise "the divisor lattice needs n >= 1" if n < 1
    values = []
    d = 1
    while d <= n
      values.push(d) if n % d == 0
      d += 1
    FiniteLattice.new(values, ->(a, b) b % a == 0)

  # All subsets of items (as arrays in item order), ordered by inclusion.
  -> .powerset(items)
    subsets = []
    count = 1 << items.size
    mask = 0
    while mask < count
      subset = []
      i = 0
      while i < items.size
        subset.push(items[i]) if ((mask >> i) & 1) != 0
        i += 1
      subsets.push(subset)
      mask += 1
    inclusion = ->(a, b)
      missing = false
      a.each ->(x)
        missing = true if !b.include?(x)
      !missing
    FiniteLattice.new(subsets, inclusion)

  # --- structure ---

  -> size
    @elements.size

  -> elements
    @elements

  -> bottom
    @elements[@bottom_index]

  -> top
    @elements[@top_index]

  -> leq?(a, b)
    @below[index_of(a)][index_of(b)]

  -> meet(a, b)
    @elements[@meet_table[index_of(a)][index_of(b)]]

  -> join(a, b)
    @elements[@join_table[index_of(a)][index_of(b)]]

  # Number of elements in a longest chain, by relaxing chain lengths over
  # the strict order until they stabilize.
  -> height
    return @height if @height != nil
    n = @elements.size
    tall = []
    n.times -> tall.push(1)
    changed = true
    while changed
      changed = false
      i = 0
      while i < n
        j = 0
        while j < n
          if j != i && @below[j][i] && tall[j] + 1 > tall[i]
            tall[i] = tall[j] + 1
            changed = true
          j += 1
        i += 1
    best = 1
    tall.each ->(h)
      best = h if h > best
    @height = best

  # --- fixpoints ---

  # True when f preserves the order: a <= b implies f(a) <= f(b). Raises if
  # f maps some element outside the lattice.
  -> monotone?(f)
    image = image_indices(f)
    i = 0
    while i < @elements.size
      j = 0
      while j < @elements.size
        return false if @below[i][j] && !@below[image[i]][image[j]]
        j += 1
      i += 1
    true

  # Least fixpoint of monotone f, by Kleene iteration from the bottom.
  -> least_fixpoint(f)
    iterate_from(@bottom_index, f)

  # Greatest fixpoint of monotone f, by Kleene iteration from the top.
  -> greatest_fixpoint(f)
    iterate_from(@top_index, f)

  # All fixpoints of f, in carrier order. For monotone f, Knaster-Tarski
  # says these form a complete lattice — see fixpoint_lattice.
  -> fixpoints(f)
    image = image_indices(f)
    found = []
    i = 0
    while i < @elements.size
      found.push(@elements[i]) if image[i] == i
      i += 1
    found

  # Elements with f(x) <= x. The least fixpoint is their meet.
  -> prefixpoints(f)
    image = image_indices(f)
    found = []
    i = 0
    while i < @elements.size
      found.push(@elements[i]) if @below[image[i]][i]
      i += 1
    found

  # Elements with x <= f(x). The greatest fixpoint is their join.
  -> postfixpoints(f)
    image = image_indices(f)
    found = []
    i = 0
    while i < @elements.size
      found.push(@elements[i]) if @below[i][image[i]]
      i += 1
    found

  # The lattice of fixpoints of monotone f, ordered as in the ambient
  # lattice. By Knaster-Tarski this is again a lattice (its meets and
  # joins need not agree with the ambient ones, so they are recomputed).
  -> fixpoint_lattice(f)
    require_monotone!(f)
    FiniteLattice.new(fixpoints(f), @leq)

  # --- internals ---

  -> index_of(value)
    i = @elements.index(value)
    raise value.to_s + " is not an element of the lattice" if i == nil
    i

  -> image_indices(f)
    image = []
    @elements.each ->(e)
      out = f.call(e)
      i = @elements.index(out)
      if i == nil
        raise "f maps " + e.to_s + " to " + out.to_s + ", outside the lattice"
      image.push(i)
    image

  -> require_monotone!(f)
    raise "the function is not monotone" if !monotone?(f)

  -> iterate_from(start, f)
    require_monotone!(f)
    image = image_indices(f)
    current = start
    steps = 0
    while image[current] != current
      current = image[current]
      steps += 1
      raise "fixpoint iteration failed to converge" if steps > @elements.size
    @elements[current]

  -> build_order!
    n = @elements.size
    @below = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < n
        row.push(@leq.call(@elements[i], @elements[j]) ? true : false)
        j += 1
      @below.push(row)
      i += 1
    i = 0
    while i < n
      raise "the order is not reflexive" if !@below[i][i]
      j = 0
      while j < n
        if i != j && @below[i][j] && @below[j][i]
          raise "the order is not antisymmetric (duplicate elements?)"
        j += 1
      i += 1
    i = 0
    while i < n
      j = 0
      while j < n
        if @below[i][j]
          k = 0
          while k < n
            raise "the order is not transitive" if @below[j][k] && !@below[i][k]
            k += 1
        j += 1
      i += 1

  -> build_tables!
    n = @elements.size
    @meet_table = []
    @join_table = []
    i = 0
    while i < n
      meets = []
      joins = []
      j = 0
      while j < n
        meets.push(bound_index(i, j, true))
        joins.push(bound_index(i, j, false))
        j += 1
      @meet_table.push(meets)
      @join_table.push(joins)
      i += 1
    @bottom_index = 0
    @top_index = 0
    i = 0
    while i < n
      @bottom_index = @meet_table[@bottom_index][i]
      @top_index = @join_table[@top_index][i]
      i += 1
    @height = nil

  # Index of the meet (lower = true) or join (lower = false) of i and j:
  # the greatest lower bound / least upper bound among the shared bounds.
  -> bound_index(i, j, lower)
    n = @elements.size
    bounds = []
    k = 0
    while k < n
      inside = lower ? (@below[k][i] && @below[k][j]) : (@below[i][k] && @below[j][k])
      bounds.push(k) if inside
      k += 1
    best = nil
    bounds.each ->(candidate)
      extreme = true
      bounds.each ->(other)
        ordered = lower ? @below[other][candidate] : @below[candidate][other]
        extreme = false if !ordered
      best = candidate if extreme
    if best == nil
      kind = lower ? "meet" : "join"
      raise "no " + kind + " for " + @elements[i].to_s + " and " + @elements[j].to_s + ": not a lattice"
    best
