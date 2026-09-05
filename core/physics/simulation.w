# EulerSimulation — the dimensioned, user-facing layer over FiniteVolume.
#
# Configuration accepts units of measurement (Quantities) everywhere a
# physical quantity appears — domain lengths in m/km, end time in s/ms,
# thermal velocity in m/s, pressures in Pa/atm — and converts configuration
# values to raw SI f64 before solver construction. Initial-condition lambdas
# return primitive SI arrays. Captured frames are 8-bit quantized fields for
# the Plot3D web viewer, not lossless solver state.
#
#   sim = EulerSimulation.compressible(2)
#     .titled("2D Riemann problem")
#     .resolution([400, 400])
#     .domain([1 m, 1 m])
#     .gas_gamma(1.4)
#     .duration(0.3 s)
#     .capture([:rho, :pressure], 60)
#   sim.init ->(x, y) [...]
#   sim.run!
#   sim.view!                       # writes + opens the three.js viewer
#
# All builder methods return self for chaining.

+ EulerSimulation
  -> .compressible(dim)
    EulerSimulation.new(:compressible, dim)

  -> .isothermal(dim)
    EulerSimulation.new(:isothermal, dim)

  -> new(mode, dim)
    if mode != :compressible && mode != :isothermal
      raise "EulerSimulation: mode must be compressible or isothermal"
    if !Physics.integer?(dim) || dim < 1 || dim > 3
      raise "EulerSimulation: dim must be 1, 2, or 3"
    @mode = mode
    @dim = dim
    @title = "euler simulation"
    @cells = nil
    @lengths_si = nil
    @gamma = ~1.4
    @vt_si = ~1.0
    @cfl = nil
    @t_end_si = ~1.0
    @frame_count = 40
    @capture_fields = [:rho]
    @bc = [:outflow]
    @bc_faces = []
    @init_fn = nil
    @solid_fn = nil
    @fv = nil
    @frames = []
    @mask_b64 = nil
    @extra_meta = {}

  -> titled(name)
    @title = name
    self

  -> resolution(cells)
    if cells.class_name != "Array" || cells.size != @dim
      raise "EulerSimulation: resolution needs [@dim] entries"
    cells.each -> (count)
      if !Physics.integer?(count) || count <= 0
        raise "EulerSimulation: resolution entries must be positive Integers"
    @cells = cells.dup
    self

  # Domain lengths: Quantities (any length unit) or raw metres.
  -> domain(lengths)
    if lengths.class_name != "Array" || lengths.size != @dim
      raise "EulerSimulation: domain needs [@dim] entries"
    next_lengths = lengths.map -> (v) Physics.si(v, "m")
    next_lengths.each -> (length)
      if !EulerSystem.finite_number?(length) || length <= ~0.0
        raise "EulerSimulation: domain lengths must be positive and finite"
    @lengths_si = next_lengths
    self

  -> gas_gamma(value)
    next_gamma = Physics.dimensionless(value)
    if next_gamma <= ~1.0
      raise "EulerSimulation: gas gamma must be finite and greater than one"
    @gamma = next_gamma
    self

  # Isothermal thermal velocity: Quantity (speed) or raw m/s.
  -> thermal_velocity(value)
    next_vt = Physics.si(value, "m/s")
    if next_vt <= ~0.0
      raise "EulerSimulation: thermal velocity must be positive and finite"
    @vt_si = next_vt
    self

  -> courant(value)
    next_cfl = Physics.dimensionless(value)
    if next_cfl <= ~0.0 || next_cfl > ~1.0
      raise "EulerSimulation: CFL must be finite and in (0, 1]"
    @cfl = next_cfl
    self

  # Physical duration to simulate: Quantity (time) or raw seconds.
  -> duration(value)
    next_duration = Physics.si(value, "s")
    if next_duration < ~0.0
      raise "EulerSimulation: duration must be finite and nonnegative"
    @t_end_si = next_duration
    self

  # Fields to record (subset of :rho :pressure :speed :vx :vy :vz,
  # :internal_energy, :specific_internal_energy, :internal_energy_density)
  # and how many frames to
  # capture across the run.
  -> capture(fields, frame_count = 40)
    if fields.class_name != "Array" || fields.size == 0
      raise "EulerSimulation: capture needs at least one field"
    fields.each -> (name)
      supported = name == :rho || name == :pressure || name == :speed
      supported = true if name == :vx || name == :internal_energy
      supported = true if name == :specific_internal_energy
      supported = true if name == :vy || name == :vz || name == :internal_energy_density
      if !supported
        raise "EulerSimulation: unsupported capture field [name]"
      if (name == :vy && @dim < 2) || (name == :vz && @dim < 3)
        raise "EulerSimulation: velocity field direction is inactive"
      if (@mode == :isothermal &&
          (name == :internal_energy || name == :specific_internal_energy ||
           name == :internal_energy_density))
        raise "EulerSimulation: isothermal mode has no internal-energy field"
    if !Physics.integer?(frame_count) || frame_count <= 0
      raise "EulerSimulation: frame count must be a positive Integer"
    @capture_fields = fields.dup
    @frame_count = frame_count
    self

  # Boundary kind for all faces, or per-face via boundary_face.
  -> boundary(kind)
    code = FiniteVolume.boundary_code(kind)
    if code == 3
      raise "EulerSimulation: inflow needs boundary_face and a primitive state"
    @bc = [kind]
    self

  -> boundary_face(dir, side, kind, prim = nil)
    if !Physics.integer?(dir) || dir < 0 || dir >= @dim
      raise "EulerSimulation: boundary direction is out of range"
    if !Physics.integer?(side) || side < 0 || side > 1
      raise "EulerSimulation: boundary side must be 0 or 1"
    code = FiniteVolume.boundary_code(kind)
    state = nil
    if code == 3
      if prim == nil
        raise "EulerSimulation: inflow boundary needs a primitive state"
      sys = self.configured_system()
      sys.conserved(prim)
      state = prim.dup
    @bc_faces.push([dir, side, kind, state])
    self

  # Initial condition lambda (SI coordinates -> primitive SI state).
  # Dual-form: positional lambda or trailing block.
  -> init(f = nil, &)
    if f == nil
      if @dim == 1
        f = -> (x) &(x)
      elsif @dim == 2
        f = -> (x, y) &(x, y)
      else
        f = -> (x, y, z) &(x, y, z)
    @init_fn = f
    self

  # Solid (rigid body) predicate over SI coordinates.
  -> solid(f = nil, &)
    if f == nil
      if @dim == 1
        f = -> (x) &(x)
      elsif @dim == 2
        f = -> (x, y) &(x, y)
      else
        f = -> (x, y, z) &(x, y, z)
    @solid_fn = f
    self

  # Attach extra metadata shown in the viewer's parameter panel.
  -> meta(key, value)
    @extra_meta[key] = "[value]"
    self

  -> fv
    @fv

  -> frames
    @frames.dup

  -> mode
    @mode

  -> dim
    @dim

  -> title
    @title

  # -- run -------------------------------------------------------------------

  -> configured_system
    if @mode == :compressible
      return CompressibleEuler.new(@dim, @gamma)
    IsothermalEuler.new(@dim, @vt_si)

  -> build_solver
    if @cells == nil || @lengths_si == nil
      raise "EulerSimulation: resolution and domain must be set"
    if @init_fn == nil
      raise "EulerSimulation: init must be set"
    sys = self.configured_system()
    fv = FiniteVolume.new(sys, @cells, @lengths_si)
    fv.boundary(@bc[0])
    @bc_faces.each -> (spec)
      fv.boundary_face(spec[0], spec[1], spec[2], spec[3])
    fv.validate_boundaries()
    fv.cfl = @cfl if @cfl != nil
    fv.init_each(@init_fn)
    if @solid_fn != nil
      fv.solid_each(@solid_fn)
    if fv.invalid_cells() > 0
      raise "EulerSimulation: initial condition is not admissible"
    @fv = fv
    fv

  -> capture_frame
    fields = {}
    @capture_fields.each -> (name)
      raw = @fv.field(name)
      packed = Plot3D.pack_field(raw)
      fields["[name]"] = packed
    @frames.push({t: @fv.time, fields: fields})
    nil

  # Run the configured simulation from a newly built initial state, capturing
  # that state and then frame_count states at a uniform cadence
  # (frame_count + 1 total). For continuation, use fv.run_to! directly.
  # Prints one progress line per ten frames.
  -> run!
    self.build_solver()
    @frames = []
    self.capture_frame()
    n = @frame_count
    i = 1
    while i <= n
      target = @t_end_si * i.to_f() / n.to_f()
      @fv.run_to!(target)
      self.capture_frame()
      bad = @fv.invalid_cells()
      if bad > 0
        raise "EulerSimulation: [bad] cells lost admissibility at t=[@fv.time]"
      if i % 10 == 0
        << "  frame [i]/[n]  t=[@fv.time]  steps=[@fv.steps]"
      i = i + 1
    self

  # -- viewer handoff ---------------------------------------------------------

  # Full viewer spec (see core/plot3d.w for the schema).
  -> viewer_spec
    kind = "volume"
    if @dim == 1
      kind = "spacetime"
    elsif @dim == 2
      kind = "surface"
    dims = [@cells[0], 1, 1]
    dims = [@cells[0], @cells[1], 1] if @dim == 2
    dims = [@cells[0], @cells[1], @cells[2]] if @dim == 3
    dom = [@lengths_si[0], ~1.0, ~1.0]
    dom = [@lengths_si[0], @lengths_si[1], ~1.0] if @dim == 2
    dom = [@lengths_si[0], @lengths_si[1], @lengths_si[2]] if @dim == 3
    meta = {}
    meta["system"] = @mode == :compressible ? "compressible Euler [@dim]D" : "isothermal Euler [@dim]D"
    if @mode == :compressible
      meta["gamma"] = "[@gamma]"
    else
      meta["vt, m/s"] = "[@vt_si]"
    meta["resolution"] = "[@cells]"
    meta["CFL"] = "[@fv.cfl]"
    meta["duration, s"] = "[@t_end_si]"
    meta["steps"] = "[@fv.steps]"
    @extra_meta.keys.each -> (k)
      meta["[k]"] = @extra_meta[k]
    mask64 = nil
    if @solid_fn != nil
      mask64 = Base64.encode(@fv.mask_grid())
    field_names = @capture_fields.map -> (f) "[f]"
    {
      kind: kind,
      title: @title,
      dims: dims,
      domain: dom,
      fields: field_names,
      frames: @frames,
      mask: mask64,
      meta: meta
    }

  # Export the interactive three.js viewer and open it in the browser.
  -> view!(path = nil)
    out = path
    if out == nil
      slug = @title.downcase.replace(" ", "_")
      out = "/tmp/[slug]_viewer.html"
    html = Plot3D.render(self.viewer_spec())
    Plot3D.write_and_open(out, html)
    out

+ Physics
  -> .compressible_simulation(dim)
    EulerSimulation.compressible(dim)

  -> .isothermal_simulation(dim)
    EulerSimulation.isothermal(dim)
