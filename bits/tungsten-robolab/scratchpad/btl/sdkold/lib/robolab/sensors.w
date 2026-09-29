# Frame: one tick of sensation from the body.
#
# Proprioception first (per muscle: contraction c, contraction rate cdot, and
# force as a fraction of peak, the muscle spindle and Golgi tendon organ
# signals), then named sensor blocks declared in the handshake (body state,
# contacts, task objects such as a ball). The schema maps a block name to
# its offset and width in the flat value array.

+ Schema
  ro :muscle_count
  -> new(@muscle_count)
    @offsets = {}
    @widths = {}
    @names = []
    @next = 1 + 3 * @muscle_count

  -> add(name, width)
    @offsets[name] = @next
    @widths[name] = width
    @names.push(name)
    @next += width
    self

  -> has?(name)
    @offsets.key?(name)

  -> offset(name)
    raise "no sensor [name]" if !@offsets.key?(name)
    @offsets[name]

  -> width(name)
    @widths[name]

  -> names
    @names

+ Frame
  ro :values
  ro :schema
  -> new(@schema, @values)

  -> t
    @values[0]

  -> muscle_count
    @schema.muscle_count

  -> c(i)
    @values[1 + i]

  -> cdot(i)
    @values[1 + @schema.muscle_count + i]

  -> force(i)
    @values[1 + 2 * @schema.muscle_count + i]

  -> has?(name)
    @schema.has?(name)

  # Scalar sensor (first component of the block).
  -> get(name)
    @values[@schema.offset(name)]

  # Component k of a vector sensor.
  -> at(name, k)
    @values[@schema.offset(name) + k]

  -> vec(name)
    o = @schema.offset(name)
    (0...@schema.width(name)).map -> @values[o + item]

  # Conveniences for the standard block.
  -> contact?(name, threshold = ~0.02)
    get(name + "_contact") > threshold

  -> com_x
    at("com_pos", 0)

  -> com_vx
    at("com_vel", 0)

  -> pelvis_height
    at("pelvis_pos", 2)

  # Forward lean of the torso in the sagittal plane (radians, + = forward),
  # from the torso's up axis in world coordinates.
  -> torso_pitch
    Math.atan2(at("torso_up", 0), at("torso_up", 2))

  -> torso_pitch_rate
    at("torso_angvel", 1)

  # Joint angle and rate from the "q" / "qd" sensor blocks (multi-joint bodies).
  -> q(body, joint)
    at("q", body.geometry.joint(joint))

  -> qd(body, joint)
    at("qd", body.geometry.joint(joint))

  # Joint angle from the pos muscle's contraction.
  -> joint_angle(body, joint)
    body.muscle(body.pos_index(joint)).angle_at(c(body.pos_index(joint)))

  -> joint_rate(body, joint)
    m = body.muscle(body.pos_index(joint))
    cdot(body.pos_index(joint)) * (m.qmax - m.qmin)
