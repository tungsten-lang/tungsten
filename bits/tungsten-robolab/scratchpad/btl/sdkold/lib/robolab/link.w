# StdioLink: the controller's side of the bus to the body.
#
# Speaks the robolab line protocol (see playground/bridge.py): a handshake
# that describes the muscles, sensor blocks, and parameter overrides, then
# one `S ...` sensor line in and one `A ...` activation line out per tick.
# Any transport that carries these lines (a pipe to MuJoCo today, a serial
# link to real actuators later) can host the same controller.

+ StdioLink
  ro :body
  ro :schema
  ro :params
  ro :dt
  ro :task
  -> new
    @body = Body.new
    @schema = nil
    @params = {}
    @dt = ~0.005
    @task = ""
    @sensors = []

  -> handshake
    line = gets
    raise "robolab: expected ROBOLAB header, got [line]" if line == nil || !line.starts_with?("ROBOLAB")
    line = gets
    while line != nil && line != "BEGIN"
      tok = line.split(" ")
      kind = tok[0]
      if kind == "TASK"
        @task = tok[1]
      if kind == "DT"
        @dt = tok[1].to_f
      if kind == "MUSCLE"
        @body.add(Muscle.new(tok[1].to_i, tok[2], tok[3], tok[4].to_i, tok[5].to_f, tok[6].to_f, tok[7]))
      if kind == "SENSOR"
        @sensors.push([tok[1], tok[2].to_i])
      if kind == "PARAM"
        @params[tok[1]] = tok[2].to_f
      if kind == "JOINT"
        @body.set_geometry(Geometry.new) if @body.geometry == nil
        @body.geometry.add_joint(tok[1].to_i, tok[2], tok[3].to_f, tok[4].to_f, tok[5].to_f, tok[6].to_i)
      if kind == "MRANGE"
        @body.geometry.set_range(tok[1].to_i, tok[2].to_f, tok[3].to_f, tok[4].to_f)
      if kind == "MLEN"
        vals = (3...tok.size).map -> tok[item].to_f
        @body.geometry.add_length(tok[1].to_i, tok[2].to_i, vals)
      if kind == "MFORCE"
        @body.geometry.set_force(tok[1].to_i, tok[2].to_f)
      if kind == "MPAIR"
        vals = (5...tok.size).map -> tok[item].to_f
        @body.geometry.add_pair(tok[1].to_i, tok[2].to_i, tok[3].to_i, tok[4].to_i, vals)
      if kind == "MOTOR"
        @body.add_motor(tok[2])
      line = gets
    @schema = Schema.new(@body.size)
    @sensors.each -> @schema.add(item[0], item[1])
    self

  -> describe?
    @params.key?("__describe")

  -> serve(ctl)
    n = @body.size
    << "READY [n]"
    if describe?
      # Run one tick on an all-zero frame so the skill's start declares its
      # tunables, then list them.
      width = 1 + 3 * n
      @schema.names.each -> width += @schema.width(item)
      ctl.tick(Frame.new(@schema, (0...width).map -> ~0.0))
      ctl.skill.describe.each -> << item
      << "END"
      return self
    line = gets
    while line != nil
      tok = line.split(" ")
      vals = (1...tok.size).map -> tok[item].to_f
      frame = Frame.new(@schema, vals)
      acts = ctl.tick(frame)
      tg = ctl.target
      out = "A " + acts.join(" ") + " " + tg.join(" ") + " " + ctl.label
      ctl.take_emits.each -> out = out + " " + item
      << out
      line = gets
    self

# Entry point shared by every robolab binary: `factory` builds the skill
# from the body and parameters the handshake delivered.
+ Robolab
  -> .serve(factory)
    link = StdioLink.new
    link.handshake
    skill = factory.call(link.body, link.params)
    ctl = Controller.new(link.body, link.dt, skill)
    link.serve(ctl)
