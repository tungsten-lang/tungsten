# Finite-volume wave-propagation solver for the Euler systems on uniform
# Cartesian grids in 1/2/3 dimensions.
#
# Method (LeVeque wave propagation with the verified Lanyon blocks):
#   - minmod reconstruction of one-sided cell-edge states,
#   - Lax–Friedrichs two-wave fluctuations A∓ΔU at every interface,
#   - intra-cell edge-flux difference F(U_i^R) − F(U_i^L),
#   - unsplit accumulation over directions, SSP-RK2 (Heun) in time,
#   - CFL timestep from the per-direction maximum wavespeeds.
#
#     U_i ← U_i − Δt·Σ_d (1/Δx_d)·[ A⁺ΔU_{i−½,d} + A⁻ΔU_{i+½,d}
#                                   + F_d(U_i^R) − F_d(U_i^L) ]
#
# Storage is a single flat f64[] in array-of-cells layout: component c of
# cell (i,j,k) lives at ((k·ny + j)·nx + i)·ns + c, with a two-cell ghost
# ring in every active dimension. All hot kernels are class methods with
# typed signatures operating on parameter arrays only (raw machine loops:
# counters are `## i64`, scratch buffers are caller-provided f64[] slabs,
# no conditional expressions, no nested user calls).
#
# Boundary kinds per face: 0 periodic · 1 outflow · 2 reflect · 3 inflow
# (fixed conserved state). Rigid embedded bodies use a stair-step cell
# mask: solid cells are mirror-filled before each directional sweep and
# interfaces into solid cells are solved against the mirrored state, which
# realizes a reflecting wall on the staircase boundary.

+ FiniteVolume
  # -- construction ---------------------------------------------------------

  # sys: a CompressibleEuler or IsothermalEuler instance.
  # cells: interior cell counts, one per dimension, e.g. [400, 400].
  # lengths: physical domain lengths in metres (raw numbers), same arity.
  -> new(sys, cells, lengths)
    if cells.size != sys.dim || lengths.size != sys.dim
      raise "FiniteVolume: cells/lengths must have [sys.dim] entries"
    if !sys.params_valid?
      raise "FiniteVolume: invalid system parameters"
    @sys = sys
    @dim = sys.dim
    @ns = sys.nstate
    @compressible = sys.compressible?
    @gamma = ~0.0
    @vt = ~0.0
    if @compressible
      @gamma = sys.gas_gamma
    else
      @vt = sys.vt
    @cells = cells
    @nx = cells[0] + 4
    @ny = 1
    @nz = 1
    @ny = cells[1] + 4 if @dim >= 2
    @nz = cells[2] + 4 if @dim >= 3
    @lengths = lengths
    @dx = [~0.0, ~1.0, ~1.0]
    @dx[0] = lengths[0].to_f() / cells[0].to_f()
    @dx[1] = lengths[1].to_f() / cells[1].to_f() if @dim >= 2
    @dx[2] = lengths[2].to_f() / cells[2].to_f() if @dim >= 3
    @ncells = @nx * @ny * @nz
    total = @ncells * @ns
    @q = f64[total]
    @q0 = f64[total]
    @dq = f64[total]
    @ql = f64[total]
    @qr = f64[total]
    @mask = u8[@ncells]
    @scratch_ul = f64[8]
    @scratch_ur = f64[8]
    @scratch_fl = f64[8]
    @scratch_fr = f64[8]
    @amax_out = f64[4]
    # Face boundary kinds, indexed [2*dir + side]: default outflow.
    @bc_kind = [1, 1, 1, 1, 1, 1]
    @bc_lo = f64[8]
    @bc_hi = f64[8]
    @cfl = ~0.4 / @dim.to_f()
    @time = ~0.0
    @steps = 0

  -> sys
    @sys

  -> time
    @time

  -> steps
    @steps

  -> cells
    @cells

  -> dx(dir)
    @dx[dir]

  -> cfl
    @cfl

  -> cfl=(value)
    @cfl = Physics.dimensionless(value)

  # Set every face to one boundary kind (:periodic, :outflow, :reflect).
  -> boundary(kind)
    d = 0
    while d < 3
      self.boundary_face(d, 0, kind, nil)
      self.boundary_face(d, 1, kind, nil)
      d = d + 1
    self

  # Set one face. dir 0..2, side 0 = low, 1 = high. For :inflow pass the
  # primitive state [rho, v..., p] that should stream in.
  -> boundary_face(dir, side, kind, prim = nil)
    code = 1
    case kind
      when :periodic
        code = 0
      when :outflow
        code = 1
      when :reflect
        code = 2
      when :inflow
        code = 3
      else
        raise "FiniteVolume: unknown boundary kind [kind]"
    @bc_kind[2 * dir + side] = code
    if code == 3
      if prim == nil
        raise "FiniteVolume: inflow boundary needs a primitive state"
      u = @sys.conserved(prim)
      k = 0
      while k < @ns
        if side == 0
          @bc_lo[k] = u[k]
        else
          @bc_hi[k] = u[k]
        k = k + 1
    self

  # -- coordinates and cell access ------------------------------------------

  # Cell-centre coordinate of interior cell index along dir (0-based).
  -> centre(dir, i)
    (i.to_f() + ~0.5) * @dx[dir]

  # Storage index of interior cell (i[, j[, k]]) — components at ·ns.
  -> cell_index(i, j = 0, k = 0)
    jj = 0
    kk = 0
    jj = j + 2 if @dim >= 2
    kk = k + 2 if @dim >= 3
    ((kk * @ny + jj) * @nx + (i + 2))

  -> set_cell(i, j, k, prim)
    u = @sys.conserved(prim)
    base = self.cell_index(i, j, k) * @ns
    c = 0
    while c < @ns
      @q[base + c] = u[c]
      c = c + 1
    nil

  -> cell(i, j = 0, k = 0)
    base = self.cell_index(i, j, k) * @ns
    u = []
    c = 0
    while c < @ns
      u.push(@q[base + c])
      c = c + 1
    u

  # Initialize every interior cell from a lambda (x[, y[, z]]) -> primitive
  # state [rho, v..., p]; coordinates are cell centres in metres.
  # Dual-form: positional lambda (compiled) or trailing block (interpreted).
  -> init_each(f = nil, &)
    if f == nil
      if @dim == 1
        f = -> (x) &(x)
      elsif @dim == 2
        f = -> (x, y) &(x, y)
      else
        f = -> (x, y, z) &(x, y, z)
    nx = @cells[0]
    ny = 1
    nz = 1
    ny = @cells[1] if @dim >= 2
    nz = @cells[2] if @dim >= 3
    k = 0
    while k < nz
      j = 0
      while j < ny
        i = 0
        while i < nx
          prim = nil
          if @dim == 1
            prim = f.call(self.centre(0, i))
          elsif @dim == 2
            prim = f.call(self.centre(0, i), self.centre(1, j))
          else
            prim = f.call(self.centre(0, i), self.centre(1, j), self.centre(2, k))
          self.set_cell(i, j, k, prim)
          i = i + 1
        j = j + 1
      k = k + 1
    self

  # Mark solid cells from a lambda over cell-centre coordinates returning
  # true for solid. Builds the stair-step immersed boundary.
  # Dual-form: positional lambda (compiled) or trailing block (interpreted).
  -> solid_each(f = nil, &)
    if f == nil
      if @dim == 1
        f = -> (x) &(x)
      elsif @dim == 2
        f = -> (x, y) &(x, y)
      else
        f = -> (x, y, z) &(x, y, z)
    nx = @cells[0]
    ny = 1
    nz = 1
    ny = @cells[1] if @dim >= 2
    nz = @cells[2] if @dim >= 3
    count = 0
    k = 0
    while k < nz
      j = 0
      while j < ny
        i = 0
        while i < nx
          inside = false
          if @dim == 1
            inside = f.call(self.centre(0, i))
          elsif @dim == 2
            inside = f.call(self.centre(0, i), self.centre(1, j))
          else
            inside = f.call(self.centre(0, i), self.centre(1, j), self.centre(2, k))
          if inside
            @mask[self.cell_index(i, j, k)] = 1
            count = count + 1
          i = i + 1
        j = j + 1
      k = k + 1
    count

  -> solid?(i, j = 0, k = 0)
    @mask[self.cell_index(i, j, k)] == 1

  # -- native kernels -------------------------------------------------------
  # Geometry arguments (all in cell units, components resolved via ·ns):
  #   n      cells along the sweep direction (including 4 ghosts)
  #   sd     cell stride along the sweep direction
  #   na,sa  count/stride of the first transverse axis (a0: start offset)
  #   nb,sb  count/stride of the second transverse axis (b0: start offset)
  #   dm     index of the normal momentum component (1 + dir)

  # Ghost fill for one direction/kinds. kinds: 0 periodic, 1 outflow,
  # 2 reflect, 3 inflow(flo/fhi).
  -> .bc_fill(q, flo, fhi, base, n, sd, na, sa, nb, sb, ns, dm, kind_lo, kind_hi) (f64[] f64[] f64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
    b = 0 ## i64
    while b < nb
      a = 0 ## i64
      while a < na
        line = base + a * sa + b * sb
        # low side ghosts p = 0, 1
        g = 0 ## i64
        while g < 2
          dst = (line + g * sd) * ns
          src = 0 ## i64
          sign = ~1.0
          if kind_lo == 0
            src = (line + (n - 4 + g) * sd) * ns
          elsif kind_lo == 1
            src = (line + 2 * sd) * ns
          elsif kind_lo == 2
            src = (line + (3 - g) * sd) * ns
          c = 0 ## i64
          while c < ns
            v = ~0.0
            if kind_lo == 3
              v = flo[c]
            else
              v = q[src + c]
              if kind_lo == 2 && c == dm
                v = ~0.0 - v
            q[dst + c] = v
            c = c + 1
          g = g + 1
        # high side ghosts p = n-2, n-1
        g = 0 ## i64
        while g < 2
          dst = (line + (n - 2 + g) * sd) * ns
          src = 0 ## i64
          if kind_hi == 0
            src = (line + (2 + g) * sd) * ns
          elsif kind_hi == 1
            src = (line + (n - 3) * sd) * ns
          elsif kind_hi == 2
            src = (line + (n - 3 - g) * sd) * ns
          c = 0 ## i64
          while c < ns
            v = ~0.0
            if kind_hi == 3
              v = fhi[c]
            else
              v = q[src + c]
              if kind_hi == 2 && c == dm
                v = ~0.0 - v
            q[dst + c] = v
            c = c + 1
          g = g + 1
        a = a + 1
      b = b + 1
    0

  # Mirror-fill solid cells from a fluid neighbour along the sweep
  # direction (normal momentum negated) so reconstruction across the
  # staircase sees a reflecting wall.
  -> .solid_fill(q, mask, base, n, sd, na, sa, nb, sb, ns, dm) (f64[] u8[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
    b = 0 ## i64
    while b < nb
      a = 0 ## i64
      while a < na
        line = base + a * sa + b * sb
        p = 1 ## i64
        while p < n - 1
          ci = line + p * sd
          if mask[ci] == 1
            src = -1 ## i64
            if mask[ci - sd] == 0
              src = ci - sd
            elsif mask[ci + sd] == 0
              src = ci + sd
            if src >= 0
              c = 0 ## i64
              while c < ns
                v = q[src * ns + c]
                if c == dm
                  v = ~0.0 - v
                q[ci * ns + c] = v
                c = c + 1
          p = p + 1
        a = a + 1
      b = b + 1
    0

  # Minmod edge reconstruction along one direction:
  #   ql = U − ½·minmod(U−U_L, U_R−U),  qr = U + ½·minmod(U−U_L, U_R−U).
  -> .reconstruct(q, ql, qr, mask, base0, n, sd, na, sa, nb, sb, ns) (f64[] f64[] f64[] u8[] i64 i64 i64 i64 i64 i64 i64 i64) i64
    b = 0 ## i64
    while b < nb
      a = 0 ## i64
      while a < na
        line = base0 + a * sa + b * sb
        p = 1 ## i64
        while p < n - 1
          ci = line + p * sd
          base = ci * ns
          if mask[ci] == 1
            c = 0 ## i64
            while c < ns
              v = q[base + c]
              ql[base + c] = v
              qr[base + c] = v
              c = c + 1
          else
            c = 0 ## i64
            while c < ns
              u = q[base + c]
              du_l = u - q[base - sd * ns + c]
              du_r = q[base + sd * ns + c] - u
              small = du_l
              if du_r < small
                small = du_r
              large = du_l
              if du_r > large
                large = du_r
              mm = ~0.0
              if small > ~0.0
                mm = small
              if large < ~0.0
                mm = mm + large
              ql[base + c] = u - ~0.5 * mm
              qr[base + c] = u + ~0.5 * mm
              c = c + 1
          p = p + 1
        a = a + 1
      b = b + 1
    0

  # One direction of the compressible update operator: Lax–Friedrichs
  # fluctuations on reconstructed interface states plus the intra-cell
  # edge-flux difference, accumulated into dq (units of 1/time via dxinv).
  -> .sweep_ce(q, ql, qr, dq, mask, sul, sur, sfl, sfr, base0, n, sd, na, sa, nb, sb, ns, dm, gas_gamma, dxinv) (f64[] f64[] f64[] f64[] u8[] f64[] f64[] f64[] f64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 f64 f64) i64
    ie = ns - 1
    nd = ns - 2
    b = 0 ## i64
    while b < nb
      a = 0 ## i64
      while a < na
        line = base0 + a * sa + b * sb
        # interfaces between cells p and p+1 for p in [1, n-3]
        p = 1 ## i64
        while p < n - 2
          cl = line + p * sd
          cr = cl + sd
          ml = 0 ## i64
          mr = 0 ## i64
          ml = 1 if mask[cl] == 1
          mr = 1 if mask[cr] == 1
          if ml + mr < 2
            c = 0 ## i64
            while c < ns
              sul[c] = qr[cl * ns + c]
              sur[c] = ql[cr * ns + c]
              c = c + 1
            # a solid side becomes the mirror of the fluid side: rigid wall
            if mr == 1
              c = 0 ## i64
              while c < ns
                sur[c] = sul[c]
                c = c + 1
              sur[dm] = ~0.0 - sul[dm]
            if ml == 1
              c = 0 ## i64
              while c < ns
                sul[c] = sur[c]
                c = c + 1
              sul[dm] = ~0.0 - sur[dm]
            # primitive quantities on both sides
            rho_l = sul[0]
            rho_r = sur[0]
            ke_l = ~0.0
            ke_r = ~0.0
            d = 1 ## i64
            while d <= nd
              ke_l = ke_l + sul[d] * sul[d] / rho_l
              ke_r = ke_r + sur[d] * sur[d] / rho_r
              d = d + 1
            ke_l = ~0.5 * ke_l
            ke_r = ~0.5 * ke_r
            p_l = (gas_gamma - ~1.0) * (sul[ie] - ke_l)
            p_r = (gas_gamma - ~1.0) * (sur[ie] - ke_r)
            un_l = sul[dm] / rho_l
            un_r = sur[dm] / rho_r
            # Sound speeds see floored p and rho so a near-vacuum RK stage
            # cannot inject NaN into the wave decomposition; the physical
            # fluxes keep the raw values (conservation stays exact).
            ps_l = p_l
            ps_r = p_r
            if ps_l < ~1.0e-12
              ps_l = ~1.0e-12
            if ps_r < ~1.0e-12
              ps_r = ~1.0e-12
            rs_l = rho_l
            rs_r = rho_r
            if rs_l < ~1.0e-12
              rs_l = ~1.0e-12
            if rs_r < ~1.0e-12
              rs_r = ~1.0e-12
            c_l = Math.sqrt(gas_gamma * ps_l / rs_l)
            c_r = Math.sqrt(gas_gamma * ps_r / rs_r)
            al = Math.abs(un_l) + c_l
            ar = Math.abs(un_r) + c_r
            amax = al
            if ar > amax
              amax = ar
            # physical fluxes
            c = 0 ## i64
            while c < ns
              sfl[c] = ~0.0
              sfr[c] = ~0.0
              c = c + 1
            sfl[0] = sul[dm]
            sfr[0] = sur[dm]
            d = 1 ## i64
            while d <= nd
              sfl[d] = sul[dm] * sul[d] / rho_l
              sfr[d] = sur[dm] * sur[d] / rho_r
              d = d + 1
            sfl[dm] = sfl[dm] + p_l
            sfr[dm] = sfr[dm] + p_r
            sfl[ie] = (sul[ie] + p_l) * un_l
            sfr[ie] = (sur[ie] + p_r) * un_r
            # two-wave fluctuations: A− = −a·w1, A+ = a·w2
            c = 0 ## i64
            while c < ns
              du = sur[c] - sul[c]
              df = sfr[c] - sfl[c]
              w1 = ~0.5 * (du - df / amax)
              w2 = ~0.5 * (du + df / amax)
              dq[cl * ns + c] = dq[cl * ns + c] - amax * w1 * dxinv
              dq[cr * ns + c] = dq[cr * ns + c] + amax * w2 * dxinv
              c = c + 1
          p = p + 1
        # intra-cell edge-flux difference for cells p in [2, n-3]
        p = 2 ## i64
        while p < n - 2
          ci = line + p * sd
          if mask[ci] == 0
            base = ci * ns
            # left edge state -> sul, right edge state -> sur
            c = 0 ## i64
            while c < ns
              sul[c] = ql[base + c]
              sur[c] = qr[base + c]
              c = c + 1
            rho_l = sul[0]
            rho_r = sur[0]
            ke_l = ~0.0
            ke_r = ~0.0
            d = 1 ## i64
            while d <= nd
              ke_l = ke_l + sul[d] * sul[d] / rho_l
              ke_r = ke_r + sur[d] * sur[d] / rho_r
              d = d + 1
            p_l = (gas_gamma - ~1.0) * (sul[ie] - ~0.5 * ke_l)
            p_r = (gas_gamma - ~1.0) * (sur[ie] - ~0.5 * ke_r)
            un_l = sul[dm] / rho_l
            un_r = sur[dm] / rho_r
            c = 0 ## i64
            while c < ns
              fl = ~0.0
              fr = ~0.0
              if c == 0
                fl = sul[dm]
                fr = sur[dm]
              elsif c == ie
                fl = (sul[ie] + p_l) * un_l
                fr = (sur[ie] + p_r) * un_r
              else
                fl = sul[dm] * sul[c] / rho_l
                fr = sur[dm] * sur[c] / rho_r
                if c == dm
                  fl = fl + p_l
                  fr = fr + p_r
              dq[base + c] = dq[base + c] + (fr - fl) * dxinv
              c = c + 1
          p = p + 1
        a = a + 1
      b = b + 1
    0

  # Isothermal twin of sweep_ce (no energy equation; p = ρ·vt²).
  -> .sweep_ie(q, ql, qr, dq, mask, sul, sur, sfl, sfr, base0, n, sd, na, sa, nb, sb, ns, dm, vt, dxinv) (f64[] f64[] f64[] f64[] u8[] f64[] f64[] f64[] f64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 f64 f64) i64
    nd = ns - 1
    b = 0 ## i64
    while b < nb
      a = 0 ## i64
      while a < na
        line = base0 + a * sa + b * sb
        p = 1 ## i64
        while p < n - 2
          cl = line + p * sd
          cr = cl + sd
          ml = 0 ## i64
          mr = 0 ## i64
          ml = 1 if mask[cl] == 1
          mr = 1 if mask[cr] == 1
          if ml + mr < 2
            c = 0 ## i64
            while c < ns
              sul[c] = qr[cl * ns + c]
              sur[c] = ql[cr * ns + c]
              c = c + 1
            if mr == 1
              c = 0 ## i64
              while c < ns
                sur[c] = sul[c]
                c = c + 1
              sur[dm] = ~0.0 - sul[dm]
            if ml == 1
              c = 0 ## i64
              while c < ns
                sul[c] = sur[c]
                c = c + 1
              sul[dm] = ~0.0 - sur[dm]
            rho_l = sul[0]
            rho_r = sur[0]
            un_l = sul[dm] / rho_l
            un_r = sur[dm] / rho_r
            al = Math.abs(un_l) + vt
            ar = Math.abs(un_r) + vt
            amax = al
            if ar > amax
              amax = ar
            sfl[0] = sul[dm]
            sfr[0] = sur[dm]
            d = 1 ## i64
            while d <= nd
              sfl[d] = sul[dm] * sul[d] / rho_l
              sfr[d] = sur[dm] * sur[d] / rho_r
              d = d + 1
            sfl[dm] = sfl[dm] + rho_l * vt * vt
            sfr[dm] = sfr[dm] + rho_r * vt * vt
            c = 0 ## i64
            while c < ns
              du = sur[c] - sul[c]
              df = sfr[c] - sfl[c]
              w1 = ~0.5 * (du - df / amax)
              w2 = ~0.5 * (du + df / amax)
              dq[cl * ns + c] = dq[cl * ns + c] - amax * w1 * dxinv
              dq[cr * ns + c] = dq[cr * ns + c] + amax * w2 * dxinv
              c = c + 1
          p = p + 1
        p = 2 ## i64
        while p < n - 2
          ci = line + p * sd
          if mask[ci] == 0
            base = ci * ns
            c = 0 ## i64
            while c < ns
              sul[c] = ql[base + c]
              sur[c] = qr[base + c]
              c = c + 1
            rho_l = sul[0]
            rho_r = sur[0]
            un_l = sul[dm] / rho_l
            un_r = sur[dm] / rho_r
            c = 0 ## i64
            while c < ns
              fl = ~0.0
              fr = ~0.0
              if c == 0
                fl = sul[dm]
                fr = sur[dm]
              else
                fl = sul[dm] * sul[c] / rho_l
                fr = sur[dm] * sur[c] / rho_r
                if c == dm
                  fl = fl + rho_l * vt * vt
                  fr = fr + rho_r * vt * vt
              dq[base + c] = dq[base + c] + (fr - fl) * dxinv
              c = c + 1
          p = p + 1
        a = a + 1
      b = b + 1
    0

  # Per-direction maximum |u_n| + c over interior fluid cells, written to
  # out[0..2].
  -> .amax_ce(q, mask, out, nx, ny, nz, ns, ndim, gas_gamma) (f64[] u8[] f64[] i64 i64 i64 i64 i64 f64) i64
    out[0] = ~0.0
    out[1] = ~0.0
    out[2] = ~0.0
    ie = ns - 1
    gylo = 0 ## i64
    gzlo = 0 ## i64
    if ndim >= 2
      gylo = 2
    if ndim >= 3
      gzlo = 2
    inx = nx - 4
    iny = ny
    inz = nz
    if ndim >= 2
      iny = ny - 4
    if ndim >= 3
      inz = nz - 4
    k = 0 ## i64
    while k < inz
      j = 0 ## i64
      while j < iny
        i = 0 ## i64
        while i < inx
          ci = ((k + gzlo) * ny + (j + gylo)) * nx + (i + 2)
          if mask[ci] == 0
            base = ci * ns
            rho = q[base]
            ke = ~0.0
            d = 1 ## i64
            while d <= ndim
              ke = ke + q[base + d] * q[base + d] / rho
              d = d + 1
            pres = (gas_gamma - ~1.0) * (q[base + ie] - ~0.5 * ke)
            if pres < ~1.0e-12
              pres = ~1.0e-12
            rs = rho
            if rs < ~1.0e-12
              rs = ~1.0e-12
            cs = Math.sqrt(gas_gamma * pres / rs)
            d = 0 ## i64
            while d < ndim
              s = Math.abs(q[base + 1 + d] / rho) + cs
              if s > out[d]
                out[d] = s
              d = d + 1
          i = i + 1
        j = j + 1
      k = k + 1
    0

  -> .amax_ie(q, mask, out, nx, ny, nz, ns, ndim, vt) (f64[] u8[] f64[] i64 i64 i64 i64 i64 f64) i64
    out[0] = ~0.0
    out[1] = ~0.0
    out[2] = ~0.0
    gylo = 0 ## i64
    gzlo = 0 ## i64
    if ndim >= 2
      gylo = 2
    if ndim >= 3
      gzlo = 2
    inx = nx - 4
    iny = ny
    inz = nz
    if ndim >= 2
      iny = ny - 4
    if ndim >= 3
      inz = nz - 4
    k = 0 ## i64
    while k < inz
      j = 0 ## i64
      while j < iny
        i = 0 ## i64
        while i < inx
          ci = ((k + gzlo) * ny + (j + gylo)) * nx + (i + 2)
          if mask[ci] == 0
            base = ci * ns
            rho = q[base]
            d = 0 ## i64
            while d < ndim
              s = Math.abs(q[base + 1 + d] / rho) + vt
              if s > out[d]
                out[d] = s
              d = d + 1
          i = i + 1
        j = j + 1
      k = k + 1
    0

  -> .kernel_copy(dst, src, total) (f64[] f64[] i64) i64
    i = 0 ## i64
    while i < total
      dst[i] = src[i]
      i = i + 1
    0

  -> .kernel_zero(dst, total) (f64[] i64) i64
    i = 0 ## i64
    while i < total
      dst[i] = ~0.0
      i = i + 1
    0

  # q ← q − dt·dq  (solid cells too; they are refilled before use).
  -> .kernel_apply(q, dq, total, dt) (f64[] f64[] i64 f64) i64
    i = 0 ## i64
    while i < total
      q[i] = q[i] - dt * dq[i]
      i = i + 1
    0

  # q ← ½(q + q0)  — final SSP-RK2 combination.
  -> .kernel_average(q, q0, total) (f64[] f64[] i64) i64
    i = 0 ## i64
    while i < total
      q[i] = ~0.5 * (q[i] + q0[i])
      i = i + 1
    0

  # Extract a derived field over the interior into out (viewer order:
  # x fastest). what: 0 density, 1 pressure, 2 speed, 3 normal-x velocity,
  # 4 specific internal energy. Solid cells emit the fill value.
  -> .extract_ce(q, mask, out, nx, ny, nz, ns, ndim, gas_gamma, what, fill) (f64[] u8[] f64[] i64 i64 i64 i64 i64 f64 i64 f64) i64
    ie = ns - 1
    gxlo = 2 ## i64
    gylo = 0 ## i64
    gzlo = 0 ## i64
    if ndim >= 2
      gylo = 2
    if ndim >= 3
      gzlo = 2
    inx = nx - 4
    iny = ny
    inz = nz
    if ndim >= 2
      iny = ny - 4
    if ndim >= 3
      inz = nz - 4
    w = 0 ## i64
    k = 0 ## i64
    while k < inz
      j = 0 ## i64
      while j < iny
        i = 0 ## i64
        while i < inx
          ci = ((k + gzlo) * ny + (j + gylo)) * nx + (i + gxlo)
          if mask[ci] == 1
            out[w] = fill
          else
            base = ci * ns
            rho = q[base]
            ke = ~0.0
            d = 1 ## i64
            while d <= ndim
              ke = ke + q[base + d] * q[base + d] / rho
              d = d + 1
            pres = (gas_gamma - ~1.0) * (q[base + ie] - ~0.5 * ke)
            v = rho
            if what == 1
              v = pres
            elsif what == 2
              v = Math.sqrt(ke / rho)
            elsif what == 3
              v = q[base + 1] / rho
            elsif what == 4
              v = (q[base + ie] - ~0.5 * ke) / rho
            out[w] = v
          w = w + 1
          i = i + 1
        j = j + 1
      k = k + 1
    0

  -> .extract_ie(q, mask, out, nx, ny, nz, ns, ndim, vt, what, fill) (f64[] u8[] f64[] i64 i64 i64 i64 i64 f64 i64 f64) i64
    gxlo = 2 ## i64
    gylo = 0 ## i64
    gzlo = 0 ## i64
    if ndim >= 2
      gylo = 2
    if ndim >= 3
      gzlo = 2
    inx = nx - 4
    iny = ny
    inz = nz
    if ndim >= 2
      iny = ny - 4
    if ndim >= 3
      inz = nz - 4
    w = 0 ## i64
    k = 0 ## i64
    while k < inz
      j = 0 ## i64
      while j < iny
        i = 0 ## i64
        while i < inx
          ci = ((k + gzlo) * ny + (j + gylo)) * nx + (i + gxlo)
          if mask[ci] == 1
            out[w] = fill
          else
            base = ci * ns
            rho = q[base]
            ke = ~0.0
            d = 1 ## i64
            while d <= ndim
              ke = ke + q[base + d] * q[base + d] / rho
              d = d + 1
            v = rho
            if what == 1
              v = rho * vt * vt
            elsif what == 2
              v = Math.sqrt(ke / rho)
            elsif what == 3
              v = q[base + 1] / rho

            out[w] = v
          w = w + 1
          i = i + 1
        j = j + 1
      k = k + 1
    0

  # Interior sums of the conserved components (mass, momenta, energy) —
  # the conservation diagnostics. Writes into out[0..ns-1].
  -> .kernel_totals(q, mask, out, nx, ny, nz, ns, ndim) (f64[] u8[] f64[] i64 i64 i64 i64 i64) i64
    c = 0 ## i64
    while c < ns
      out[c] = ~0.0
      c = c + 1
    gxlo = 2 ## i64
    gylo = 0 ## i64
    gzlo = 0 ## i64
    if ndim >= 2
      gylo = 2
    if ndim >= 3
      gzlo = 2
    inx = nx - 4
    iny = ny
    inz = nz
    if ndim >= 2
      iny = ny - 4
    if ndim >= 3
      inz = nz - 4
    k = 0 ## i64
    while k < inz
      j = 0 ## i64
      while j < iny
        i = 0 ## i64
        while i < inx
          ci = ((k + gzlo) * ny + (j + gylo)) * nx + (i + gxlo)
          if mask[ci] == 0
            base = ci * ns
            c = 0 ## i64
            while c < ns
              out[c] = out[c] + q[base + c]
              c = c + 1
          i = i + 1
        j = j + 1
      k = k + 1
    0

  # Positivity scan: returns the count of interior fluid cells with
  # non-positive density (or energy for compressible systems).
  -> .kernel_invalid(q, mask, nx, ny, nz, ns, ndim, compressible) (f64[] u8[] i64 i64 i64 i64 i64 i64) i64
    bad = 0 ## i64
    ie = ns - 1
    gxlo = 2 ## i64
    gylo = 0 ## i64
    gzlo = 0 ## i64
    if ndim >= 2
      gylo = 2
    if ndim >= 3
      gzlo = 2
    inx = nx - 4
    iny = ny
    inz = nz
    if ndim >= 2
      iny = ny - 4
    if ndim >= 3
      inz = nz - 4
    k = 0 ## i64
    while k < inz
      j = 0 ## i64
      while j < iny
        i = 0 ## i64
        while i < inx
          ci = ((k + gzlo) * ny + (j + gylo)) * nx + (i + gxlo)
          if mask[ci] == 0
            base = ci * ns
            if q[base] <= ~0.0
              bad = bad + 1
            elsif compressible == 1 && q[base + ie] <= ~0.0
              bad = bad + 1
          i = i + 1
        j = j + 1
      k = k + 1
    bad

  # -- driver ---------------------------------------------------------------

  # Geometry tuple for a sweep along dir: [n, sd, na, sa, a0, nb, sb, b0].
  # Transverse ranges cover only interior cells for sweeps; boundary fills
  # span the full transverse extent so edges and corners populate.
  -> geometry(dir, full)
    sx = 1
    sy = @nx
    sz = @nx * @ny
    n = @nx
    sd = sx
    ta = [@ny, sy, @dim >= 2 ? 2 : 0]
    tb = [@nz, sz, @dim >= 3 ? 2 : 0]
    if dir == 1
      n = @ny
      sd = sy
      ta = [@nx, sx, 2]
      tb = [@nz, sz, @dim >= 3 ? 2 : 0]
    elsif dir == 2
      n = @nz
      sd = sz
      ta = [@nx, sx, 2]
      tb = [@ny, sy, 2]
    na = ta[0]
    a0 = 0
    nb = tb[0]
    b0 = 0
    if !full
      na = ta[0] - 2 * ta[2]
      a0 = ta[2]
      nb = tb[0] - 2 * tb[2]
      b0 = tb[2]
    [n, sd, na, ta[1], a0, nb, tb[1], b0]

  -> apply_boundaries
    dir = 0
    while dir < @dim
      g = self.geometry(dir, true)
      base = g[4] * g[3] + g[7] * g[6]
      FiniteVolume.bc_fill(@q, @bc_lo, @bc_hi, base, g[0], g[1], g[2], g[3], g[5], g[6], @ns, 1 + dir, @bc_kind[2 * dir], @bc_kind[2 * dir + 1])
      dir = dir + 1
    dir = 0
    while dir < @dim
      g = self.geometry(dir, true)
      base = g[4] * g[3] + g[7] * g[6]
      FiniteVolume.solid_fill(@q, @mask, base, g[0], g[1], g[2], g[3], g[5], g[6], @ns, 1 + dir)
      dir = dir + 1
    nil

  # Accumulate the full spatial operator into @dq (fresh).
  -> accumulate_operator
    total = @ncells * @ns
    FiniteVolume.kernel_zero(@dq, total)
    dir = 0
    while dir < @dim
      g = self.geometry(dir, false)
      dxinv = ~1.0 / @dx[dir]
      base = g[4] * g[3] + g[7] * g[6]
      FiniteVolume.reconstruct(@q, @ql, @qr, @mask, base, g[0], g[1], g[2], g[3], g[5], g[6], @ns)
      if @compressible
        FiniteVolume.sweep_ce(@q, @ql, @qr, @dq, @mask, @scratch_ul, @scratch_ur, @scratch_fl, @scratch_fr, base, g[0], g[1], g[2], g[3], g[5], g[6], @ns, 1 + dir, @gamma, dxinv)
      else
        FiniteVolume.sweep_ie(@q, @ql, @qr, @dq, @mask, @scratch_ul, @scratch_ur, @scratch_fl, @scratch_fr, base, g[0], g[1], g[2], g[3], g[5], g[6], @ns, 1 + dir, @vt, dxinv)
      dir = dir + 1
    nil

  # CFL timestep from the current state.
  -> stable_dt
    if @compressible
      FiniteVolume.amax_ce(@q, @mask, @amax_out, @nx, @ny, @nz, @ns, @dim, @gamma)
    else
      FiniteVolume.amax_ie(@q, @mask, @amax_out, @nx, @ny, @nz, @ns, @dim, @vt)
    rate = ~0.0
    dir = 0
    while dir < @dim
      rate = rate + @amax_out[dir] / @dx[dir]
      dir = dir + 1
    if rate <= ~0.0
      raise "FiniteVolume: zero wavespeed everywhere (empty or invalid state)"
    @cfl * @dim.to_f() / rate

  # One SSP-RK2 step of size dt (or the stable dt if omitted). Returns the
  # dt actually taken.
  -> step!(dt = nil)
    total = @ncells * @ns
    self.apply_boundaries()
    step_dt = dt
    if step_dt == nil
      step_dt = self.stable_dt()
    else
      step_dt = Physics.si(step_dt, "s")
    FiniteVolume.kernel_copy(@q0, @q, total)
    # stage 1
    self.accumulate_operator()
    FiniteVolume.kernel_apply(@q, @dq, total, step_dt)
    # stage 2
    self.apply_boundaries()
    self.accumulate_operator()
    FiniteVolume.kernel_apply(@q, @dq, total, step_dt)
    FiniteVolume.kernel_average(@q, @q0, total)
    @time = @time + step_dt
    @steps = @steps + 1
    step_dt

  # Advance to t_end (seconds or Quantity), invoking on_frame (if given)
  # as -> (self) after every step.
  -> run_to!(t_end, on_frame = nil)
    target = Physics.si(t_end, "s")
    while @time < target - ~1.0e-14
      dt = self.stable_dt()
      remaining = target - @time
      if dt > remaining
        dt = remaining
      self.step!(dt)
      if on_frame != nil
        on_frame.call(self)
    self

  # -- diagnostics and output ------------------------------------------------

  # Total conserved quantities over the interior (mass, momenta[, energy]).
  -> totals
    FiniteVolume.kernel_totals(@q, @mask, @scratch_fl, @nx, @ny, @nz, @ns, @dim)
    vol = ~1.0
    d = 0
    while d < @dim
      vol = vol * @dx[d]
      d = d + 1
    out = []
    c = 0
    while c < @ns
      out.push(@scratch_fl[c] * vol)
      c = c + 1
    out

  # Count of interior fluid cells violating positivity.
  -> invalid_cells
    flag = 0
    flag = 1 if @compressible
    FiniteVolume.kernel_invalid(@q, @mask, @nx, @ny, @nz, @ns, @dim, flag)

  # Field extraction into a fresh f64[] over the interior (x fastest).
  # name: :rho, :pressure, :speed, :vx, :internal_energy.
  -> field(name, fill = ~0.0)
    inx = @cells[0]
    iny = 1
    inz = 1
    iny = @cells[1] if @dim >= 2
    inz = @cells[2] if @dim >= 3
    out = f64[inx * iny * inz]
    what = 0
    case name
      when :rho
        what = 0
      when :pressure
        what = 1
      when :speed
        what = 2
      when :vx
        what = 3
      when :internal_energy
        what = 4
      else
        raise "FiniteVolume: unknown field [name]"
    if @compressible
      FiniteVolume.extract_ce(@q, @mask, out, @nx, @ny, @nz, @ns, @dim, @gamma, what, fill)
    else
      FiniteVolume.extract_ie(@q, @mask, out, @nx, @ny, @nz, @ns, @dim, @vt, what, fill)
    out

  # Interior solid mask as u8[] in the same order as field().
  -> mask_grid
    inx = @cells[0]
    iny = 1
    inz = 1
    iny = @cells[1] if @dim >= 2
    inz = @cells[2] if @dim >= 3
    out = u8[inx * iny * inz]
    w = 0
    k = 0
    while k < inz
      j = 0
      while j < iny
        i = 0
        while i < inx
          out[w] = @mask[self.cell_index(i, j, k)]
          w = w + 1
          i = i + 1
        j = j + 1
      k = k + 1
    out
