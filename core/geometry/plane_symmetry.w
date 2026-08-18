# The symmetry types a repeating plane pattern can have.
#
# Three classifications sit on top of one another. The **crystallographic
# restriction** comes first: a rotation preserving a lattice must have order
# 1, 2, 3, 4 or 6, because any other order forces two lattice points closer
# together than the shortest lattice vector. That is why five-fold symmetry
# never tiles periodically, and why the square (order 4) and triangular
# (order 6) lattices are the only interesting planar cases.
#
# From there: the **ten crystallographic point groups** are the cyclic and
# dihedral groups of those allowed orders; the **seven frieze groups**
# classify patterns repeating along one direction; and the **seventeen
# wallpaper groups** classify patterns repeating in two. The counts 10, 7 and
# 17 are theorems, and the tables below are the classification itself, in the
# standard IUC notation.

+ PlaneSymmetry
  # Rotation orders compatible with a lattice.
  -> .allowed_rotation_orders
    [1, 2, 3, 4, 6]

  -> .crystallographic?(order)
    allowed = false
    PlaneSymmetry.allowed_rotation_orders.each ->(n)
      allowed = true if n == order
    allowed

  # The ten planar crystallographic point groups: cyclic C_n and dihedral D_n
  # for each allowed rotation order.
  -> .point_groups
    out = []
    PlaneSymmetry.allowed_rotation_orders.each ->(n)
      out.push(["C[n]", n, n, false])
      out.push(["D[n]", n, 2 * n, true])
    out

  # The seven frieze groups. Each entry is
  # [IUC name, translation only?, has half turn, has vertical mirror,
  #  has horizontal mirror, has glide].
  -> .frieze_groups
    [["p1",   true,  false, false, false, false],
     ["p11g", false, false, false, false, true],
     ["p1m1", false, false, true,  false, false],
     ["p11m", false, false, false, true,  false],
     ["p2",   false, true,  false, false, false],
     ["p2mg", false, true,  true,  false, true],
     ["p2mm", false, true,  true,  true,  false]]

  # The seventeen wallpaper groups. Each entry is
  # [IUC name, highest rotation order, has reflection, has glide, lattice].
  -> .wallpaper_groups
    [["p1",    1, false, false, "oblique"],
     ["p2",    2, false, false, "oblique"],
     ["pm",    1, true,  false, "rectangular"],
     ["pg",    1, false, true,  "rectangular"],
     ["cm",    1, true,  true,  "rhombic"],
     ["pmm",   2, true,  false, "rectangular"],
     ["pmg",   2, true,  true,  "rectangular"],
     ["pgg",   2, false, true,  "rectangular"],
     ["cmm",   2, true,  true,  "rhombic"],
     ["p4",    4, false, false, "square"],
     ["p4m",   4, true,  true,  "square"],
     ["p4g",   4, true,  true,  "square"],
     ["p3",    3, false, false, "hexagonal"],
     ["p3m1",  3, true,  true,  "hexagonal"],
     ["p31m",  3, true,  true,  "hexagonal"],
     ["p6",    6, false, false, "hexagonal"],
     ["p6m",   6, true,  true,  "hexagonal"]]

  -> .wallpaper_count
    PlaneSymmetry.wallpaper_groups.size

  -> .frieze_count
    PlaneSymmetry.frieze_groups.size

  -> .point_group_count
    PlaneSymmetry.point_groups.size

  -> .wallpaper(name)
    found = nil
    PlaneSymmetry.wallpaper_groups.each ->(entry)
      found = entry if entry[0] == name
    raise "unknown wallpaper group [name]" if found == nil
    found

  # Wallpaper groups whose highest rotation is of the given order.
  -> .wallpaper_with_rotation(order)
    out = []
    PlaneSymmetry.wallpaper_groups.each ->(entry)
      out.push(entry) if entry[1] == order
    out
