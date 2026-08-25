# Chain complexes of free abelian groups and their integral homology.
#
# A complex is a list of ranks n_0, ..., n_top and boundary matrices
# d_k : Z^n_k -> Z^n_(k-1) (k = 1..top) with d_k d_(k+1) = 0. Homology is
#
#   H_k = ker d_k / im d_(k+1),
#
# and two Smith normal forms per degree compute it: the first gives a basis
# of ker d_k (the last columns of V) together with the coordinate map onto it
# (the last rows of V^-1), the second is the Smith form of im d_(k+1) written
# in those coordinates, whose cokernel is H_k with its torsion. Because the
# kernel basis is saturated, no torsion is invented or lost in the change of
# coordinates. Zero-rank chain groups are allowed; their boundary matrices are
# ignored.

+ IntegerChainComplex
  -> new(dimensions, boundaries)
    @dimensions = []
    dimensions.each ->(n)
      raise "chain group ranks must be nonnegative" if n < 0
      @dimensions.push(n)
    raise "a chain complex needs at least one chain group" if @dimensions.size == 0
    @boundaries = []
    boundaries.each ->(m)
      @boundaries.push(m)
    if @boundaries.size != @dimensions.size - 1
      raise "expected one boundary matrix per positive degree"
    @homology_cache = {}
    validate!

  # --- standard cellular complexes (one 0-cell) ---

  -> .point
    IntegerChainComplex.new([1], [])

  -> .sphere(n)
    return IntegerChainComplex.circle if n == 1
    dims = [1]
    bounds = []
    k = 1
    while k <= n
      dims.push(k == n ? 1 : 0)
      bounds.push([])
      k += 1
    dims[0] = 2 if n == 0
    IntegerChainComplex.new(dims, bounds)

  -> .circle
    IntegerChainComplex.new([1, 1], [[[0]]])

  # a b a^-1 b^-1: both boundaries vanish.
  -> .torus
    IntegerChainComplex.new([1, 2, 1], [[[0, 0]], [[0], [0]]])

  # a b a^-1 b: d(cell) = 2 b.
  -> .klein_bottle
    IntegerChainComplex.new([1, 2, 1], [[[0, 0]], [[0], [2]]])

  # a a: d(cell) = 2 a.
  -> .projective_plane
    IntegerChainComplex.new([1, 1, 1], [[[0]], [[2]]])

  # Lens space L(p, q) with one cell per dimension: d_2 = p, d_1 = d_3 = 0.
  -> .lens_space(p)
    IntegerChainComplex.new([1, 1, 1, 1], [[[0]], [[p]], [[0]]])

  # --- structure ---

  -> top_degree
    @dimensions.size - 1

  -> dimensions
    @dimensions

  -> dimension(k)
    return 0 if k < 0 || k > top_degree
    @dimensions[k]

  # Matrix of d_k, or nil when either end is zero-dimensional (or k is out
  # of range) — the map is then zero and there is nothing to store.
  -> boundary(k)
    return nil if k < 1 || k > top_degree
    return nil if @dimensions[k] == 0 || @dimensions[k - 1] == 0
    @boundaries[k - 1]

  -> validate!
    k = 1
    while k <= top_degree
      m = boundary(k)
      if m != nil
        if m.class_name != "Array" || m.size != @dimensions[k - 1]
          raise "boundary d_" + k.to_s + " must have " + @dimensions[k - 1].to_s + " rows"
        m.each ->(row)
          if row.class_name != "Array" || row.size != @dimensions[k]
            raise "boundary d_" + k.to_s + " must have " + @dimensions[k].to_s + " columns"
      k += 1
    k = 1
    while k < top_degree
      inner = boundary(k)
      outer = boundary(k + 1)
      if inner != nil && outer != nil
        product = SmithNormalForm.multiply(inner, outer)
        product.each ->(row)
          row.each ->(x)
            raise "d_" + k.to_s + " d_" + (k + 1).to_s + " != 0" if x != 0
      k += 1
    true

  -> boundary_rank(k)
    m = boundary(k)
    return 0 if m == nil
    SmithNormalForm.rank(m)

  -> cycle_rank(k)
    dimension(k) - boundary_rank(k)

  -> homology(k)
    return FinitelyGeneratedAbelianGroup.trivial if k < 0 || k > top_degree
    return @homology_cache[k] if @homology_cache.key?(k)
    @homology_cache[k] = compute_homology(k)
    @homology_cache[k]

  -> compute_homology(k)
    n = dimension(k)
    return FinitelyGeneratedAbelianGroup.trivial if n == 0
    inner = boundary(k)
    decomposition = nil
    cycles = n
    if inner != nil
      decomposition = SmithNormalForm.decompose(inner)
      cycles = decomposition.kernel_rank
    return FinitelyGeneratedAbelianGroup.trivial if cycles == 0
    outer = boundary(k + 1)
    return FinitelyGeneratedAbelianGroup.free(cycles) if outer == nil
    # im d_(k+1) in kernel coordinates: one column per (k+1)-cell.
    relations = []
    i = 0
    while i < cycles
      relations.push([])
      i += 1
    width = dimension(k + 1)
    j = 0
    while j < width
      column = SmithNormalForm.column(outer, j)
      coordinates = column
      coordinates = decomposition.kernel_coordinates(column) if decomposition != nil
      i = 0
      while i < cycles
        relations[i].push(coordinates[i])
        i += 1
      j += 1
    FinitelyGeneratedAbelianGroup.from_relations(relations)

  -> homology_groups
    out = []
    k = 0
    while k <= top_degree
      out.push(homology(k))
      k += 1
    out

  -> betti(k)
    homology(k).free_rank

  -> betti_numbers
    out = []
    k = 0
    while k <= top_degree
      out.push(betti(k))
      k += 1
    out

  -> torsion(k)
    homology(k).torsion

  # Alternating sum of the chain ranks.
  -> euler_characteristic
    total = 0
    k = 0
    while k <= top_degree
      total += k % 2 == 0 ? @dimensions[k] : 0 - @dimensions[k]
      k += 1
    total

  # Alternating sum of the Betti numbers — equal to the above by the
  # rank-nullity bookkeeping; the certificate checks it.
  -> betti_euler_characteristic
    total = 0
    k = 0
    while k <= top_degree
      total += k % 2 == 0 ? betti(k) : 0 - betti(k)
      k += 1
    total

  -> acyclic?
    k = 1
    while k <= top_degree
      return false if !homology(k).trivial?
      k += 1
    true

  # Same integral homology as the n-sphere.
  -> homology_sphere?(n)
    return false if top_degree < n
    return false if !(homology(0) == FinitelyGeneratedAbelianGroup.free(1))
    return false if !(homology(n) == FinitelyGeneratedAbelianGroup.free(1))
    k = 1
    while k <= top_degree
      return false if k != n && !homology(k).trivial?
      k += 1
    true

  -> certificate
    IntegerChainComplexCertificate.new(self)

  -> certified?
    certificate.verified?

  -> to_s
    parts = []
    homology_groups.each ->(h)
      parts.push(h.to_s)
    "IntegerChainComplex(ranks " + @dimensions.to_s + ", homology " + parts.to_s + ")"

  -> inspect
    to_s

# Re-checks d d = 0, replays every degree's ranks against the Smith forms,
# and checks the Euler characteristic two ways.
+ IntegerChainComplexCertificate
  -> new(@complex)
    @verified_cache = nil

  -> complex
    @complex

  -> proof_kind
    :smith_normal_form_homology

  -> kernel_checked?
    true

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verify!
    return false if @complex.class_name != "IntegerChainComplex"
    return false if !@complex.validate!
    k = 0
    while k <= @complex.top_degree
      h = @complex.homology(k)
      cycles = @complex.cycle_rank(k)
      boundaries = @complex.boundary_rank(k + 1)
      return false if h.free_rank != cycles - boundaries
      m = @complex.boundary(k + 1)
      if m != nil
        d = SmithNormalForm.decompose(m)
        return false if !d.certified?
        # Torsion of H_k is the torsion of coker d_(k+1) as a map into
        # Z^n_k, since ker d_k is a direct summand containing the image.
        return false if !SmithNormalForm.same_vector?(h.torsion, d.torsion)
      else
        return false if h.torsion.size != 0
      k += 1
    @complex.euler_characteristic == @complex.betti_euler_characteristic

  -> certified?
    verified?

  -> to_s
    "IntegerChainComplexCertificate(" + @complex.to_s + ")"

  -> inspect
    to_s
