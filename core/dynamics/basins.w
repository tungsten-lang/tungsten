# Basins of attraction. The CPU sweep integrates every grid cell of a
# 2-D flow and labels it by the attractor it lands nearest; the GPU
# variant of the same sweep (each cell is an independent thread) lives
# as a worked `@gpu fn` example in doc/examples/gpu_basins.w.

+ Dynamics
  # Basin grid for a 2-D flow. Each cell of the nx×ny grid over
  # [x_lo, x_hi] × [y_lo, y_hi] integrates for t_sim (RK4, step dt) and
  # is labeled with the index of the first attractor within `tol` of
  # the final state, or −1 when none is. Returns row-major rows:
  # labels[iy][ix], x varying along a row.
  -> .basins(sys, x_lo, x_hi, y_lo, y_hi, nx, ny, t_sim, dt, attractors, tol)
    steps = (t_sim / dt).to_i
    rows = []
    iy = 0
    while iy < ny
      row = []
      ix = 0
      while ix < nx
        px = x_lo + (x_hi - x_lo) * ix / (nx - 1)
        py = y_lo + (y_hi - y_lo) * iy / (ny - 1)
        xe = Dynamics.advance(sys, [px, py], ~0.0, steps, dt)
        lab = 0 - 1
        ai = 0
        while ai < attractors.size()
          if Dynamics.vdist(xe, attractors[ai]) < tol
            lab = ai
            ai = attractors.size()
          else
            ai = ai + 1
        row = row.push(lab)
        ix = ix + 1
      rows = rows.push(row)
      iy = iy + 1
    rows

  # Count of each label in a basin grid: {label => cells}.
  -> .basin_counts(rows)
    out = {}
    iy = 0
    while iy < rows.size()
      ix = 0
      while ix < rows[iy].size()
        lab = rows[iy][ix]
        if out[lab] == nil
          out[lab] = 0
        out[lab] = out[lab] + 1
        ix = ix + 1
      iy = iy + 1
    out
