# Crystallographic classification, in any dimension where it makes sense.
#
# The part that genuinely generalises is the **crystallographic restriction**.
# A rotation of order n preserving a lattice in dimension d must satisfy
#
#     phi(n) <= d
#
# because such a rotation makes the lattice a module over the ring of n-th
# cyclotomic integers, whose rank over Z is phi(n), and that rank cannot
# exceed the lattice's own. So the answer is a statement about Euler's
# totient, not a table:
#
#   d = 2, 3    n in {1, 2, 3, 4, 6}                 no five-fold symmetry
#   d = 4, 5    adds 5, 8, 10, 12                    five-fold becomes legal
#   d = 6, 7    adds 7, 9, 14, 18
#
# That is why quasicrystals are not periodic in the plane, and why they can be
# read as projections of periodic structures from higher dimensions.
#
# The classifications themselves are finite taxonomies that do not follow from
# a formula: the numbers of Bravais types, point groups and space groups are
# results, tabulated below for the dimensions where they are settled and
# deliberately absent elsewhere rather than guessed.
#
# The genuinely dimension-free counterpart of "which Bravais type is this" is
# `LatticeMetric.automorphism_group_order`, which computes a lattice's own
# symmetry group from its Gram matrix in any dimension.

+ Crystallography
  -> .totient(n)
    raise "totient needs a positive integer" if n < 1
    result = n
    remaining = n
    p = 2
    while p * p <= remaining
      if remaining % p == 0
        while remaining % p == 0
          remaining = remaining / p
        result = result - result / p
      p += 1
    result = result - result / remaining if remaining > 1
    result

  # Orders of rotation a lattice in this dimension can have.
  -> .allowed_rotation_orders(dimension)
    raise "dimension must be positive" if dimension < 1
    limit = 4 * dimension * dimension + 6
    out = []
    n = 1
    while n <= limit
      out.push(n) if Crystallography.totient(n) <= dimension
      n += 1
    out

  -> .crystallographic?(order, dimension)
    order >= 1 && Crystallography.totient(order) <= dimension

  # Bravais lattice types by dimension, for dimensions 1 to 6.
  -> .bravais_counts
    [1, 5, 14, 64, 189, 826]

  -> .bravais_count(dimension)
    counts = Crystallography.bravais_counts
    raise "Bravais counts are tabulated only for dimensions 1 to 6" if dimension < 1 || dimension > counts.size
    counts[dimension - 1]

  # Crystallographic point groups, for the dimensions where the count is
  # standard and unambiguous.
  -> .point_group_counts
    [2, 10, 32]

  -> .point_group_count(dimension)
    counts = Crystallography.point_group_counts
    raise "point group counts are tabulated only for dimensions 1 to 3" if dimension < 1 || dimension > counts.size
    counts[dimension - 1]

  # Space group types. Beyond four dimensions the enumeration exists but the
  # figures are not reproduced here.
  -> .space_group_counts
    [2, 17, 230, 4894]

  -> .space_group_count(dimension)
    counts = Crystallography.space_group_counts
    raise "space group counts are tabulated only for dimensions 1 to 4" if dimension < 1 || dimension > counts.size
    counts[dimension - 1]

  # The five plane lattice types.
  -> .bravais_types_2d
    ["oblique", "rectangular", "centred rectangular", "square", "hexagonal"]

  # The fourteen three-dimensional Bravais lattices, as
  # [name, crystal system, centring].
  -> .bravais_types_3d
    [["aP", "triclinic", "primitive"],
     ["mP", "monoclinic", "primitive"],
     ["mS", "monoclinic", "base-centred"],
     ["oP", "orthorhombic", "primitive"],
     ["oS", "orthorhombic", "base-centred"],
     ["oI", "orthorhombic", "body-centred"],
     ["oF", "orthorhombic", "face-centred"],
     ["tP", "tetragonal", "primitive"],
     ["tI", "tetragonal", "body-centred"],
     ["hR", "trigonal", "rhombohedral"],
     ["hP", "hexagonal", "primitive"],
     ["cP", "cubic", "primitive"],
     ["cI", "cubic", "body-centred"],
     ["cF", "cubic", "face-centred"]]

  -> .crystal_systems_3d
    ["triclinic", "monoclinic", "orthorhombic", "tetragonal",
     "trigonal", "hexagonal", "cubic"]

  # Five-fold symmetry is impossible periodically in the plane but legal from
  # four dimensions up, which is the arithmetic behind quasicrystals.
  -> .lowest_dimension_for_rotation(order)
    Crystallography.totient(order)
