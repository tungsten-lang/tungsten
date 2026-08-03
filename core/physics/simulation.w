# EulerSimulation — the dimensioned, user-facing layer over FiniteVolume.
#
# Configuration accepts units of measurement (Quantities) everywhere a
# physical quantity appears — domain lengths in m/km, end time in s/ms,
# thermal velocity in m/s, pressures in Pa/atm — and crosses to raw SI
# f64 exactly once, at solver construction. Initial conditions are given
# in primitive SI variables. Frames are captured as 8-bit quantized
# fields ready for the Plot3D web viewer.
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
    if cells.size != @dim
      raise "EulerSimulation: resolution needs [@dim] entries"
    @cells = cells
    self

  # Domain lengths: Quantities (any length unit) or raw metres.
  -> domain(lengths)
    if lengths.size != @dim
      raise "EulerSimulation: domain needs [@dim] entries"
    @lengths_si = lengths.map -> (v) Physics.si(v, "m")
    self

  -> gas_gamma(value)
    @gamma = Physics.dimensionless(value)
    self

  # Isothermal thermal velocity: Quantity (speed) or raw m/s.
  -> thermal_velocity(value)
    @vt_si = Physics.si(value, "m/s")
    self

  -> courant(value)
    @cfl = Physics.dimensionless(value)
    self

  # Physical duration to simulate: Quantity (time) or raw seconds.
  -> duration(value)
    @t_end_si = Physics.si(value, "s")
    self

  # Fields to record (subset of :rho :pressure :speed :vx
  # :internal_energy) and how many frames to capture across the run.
  -> capture(fields, frame_count = 40)
    @capture_fields = fields
    @frame_count = frame_count
    self

  # Boundary kind for all faces, or per-face via boundary_face.
  -> boundary(kind)
    @bc = [kind]
    self

  -> boundary_face(dir, side, kind, prim = nil)
    @bc_faces.push([dir, side, kind, prim])
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
    @frames

  -> title
    @title

  # -- run -------------------------------------------------------------------

  -> build_solver
    if @cells == nil || @lengths_si == nil
      raise "EulerSimulation: resolution and domain must be set"
    if @init_fn == nil
      raise "EulerSimulation: init must be set"
    sys = nil
    if @mode == :compressible
      sys = CompressibleEuler.new(@dim, @gamma)
    else
      sys = IsothermalEuler.new(@dim, @vt_si)
    fv = FiniteVolume.new(sys, @cells, @lengths_si)
    fv.boundary(@bc[0])
    @bc_faces.each -> (spec)
      fv.boundary_face(spec[0], spec[1], spec[2], spec[3])
    fv.cfl = @cfl if @cfl != nil
    fv.init_each(@init_fn)
    if @solid_fn != nil
      fv.solid_each(@solid_fn)
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

  # Run the configured simulation, capturing frames at a uniform cadence.
  # Prints one progress line per ten frames.
  -> run!
    self.build_solver() if @fv == nil
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
        raise "EulerSimulation: [bad] cells lost positivity at t=[@fv.time]"
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
