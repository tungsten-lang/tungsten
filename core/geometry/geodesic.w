# GeodesicSystem — affine geodesic equations generated from a Metric.
#
# State layout is [x^0, ..., x^(n-1), v^0, ..., v^(n-1)].

+ GeodesicTrajectory
  -> new(@system, @raw)

  -> system
    @system

  -> chart
    @system.metric.chart

  -> parameters
    Geometry.deep_copy(@raw[:t])

  -> states
    Geometry.deep_copy(@raw[:y])

  -> positions
    out = []
    @raw[:y].each -> (state)
      position = []
      i = 0
      while i < @system.dimension
        position.push(state[i])
        i += 1
      out.push(position)
    out

  -> velocities
    out = []
    @raw[:y].each -> (state)
      velocity = []
      i = 0
      while i < @system.dimension
        velocity.push(state[@system.dimension + i])
        i += 1
      out.push(velocity)
    out

  -> final_state
    values = @raw[:y]
    Geometry.deep_copy(values[values.size - 1])

  -> final_position
    values = self.positions
    values[values.size - 1]

  -> final_velocity
    values = self.velocities
    values[values.size - 1]

  -> to_s
    "GeodesicTrajectory(points=" + @raw[:t].size.to_s + ")"

  -> inspect
    to_s


+ GeodesicSystem
  -> new(@metric)
    if @metric.class_name != "Metric"
      raise "geodesic system needs a Metric"

  -> metric
    @metric

  -> dimension
    @metric.dimension

  -> rhs(affine_parameter, state)
    if state.class_name != "Array" || state.size != 2 * self.dimension
      raise "geodesic state must contain one position and velocity per coordinate"
    position = []
    velocity = []
    i = 0
    while i < self.dimension
      position.push(state[i])
      velocity.push(state[self.dimension + i])
      i += 1
    gamma = @metric.connection.evaluate(position)
    out = []
    velocity.each -> (component) out.push(component)
    upper = 0
    while upper < self.dimension
      acceleration = ~0.0
      left = 0
      while left < self.dimension
        right = 0
        while right < self.dimension
          acceleration -= gamma[upper][left][right] * (
            velocity[left] * velocity[right])
          right += 1
        left += 1
      out.push(acceleration)
      upper += 1
    out

  -> trajectory(initial_position, initial_velocity,
                  start_parameter, stop_parameter,
                  step = ~0.01, method = :rk4)
    if initial_position.class_name != "Array" || (
       initial_position.size != self.dimension)
      raise "initial geodesic position has the wrong dimension"
    if initial_velocity.class_name != "Array" || (
       initial_velocity.size != self.dimension)
      raise "initial geodesic velocity has the wrong dimension"
    state = []
    initial_position.each -> (component) state.push(component)
    initial_velocity.each -> (component) state.push(component)
    system = self
    equation = -> (parameter, values)
      system.rhs(parameter, values)
    result = Solve.ivp(
      equation, start_parameter, stop_parameter, state, method, step)
    GeodesicTrajectory.new(self, result)

  -> to_s
    "GeodesicSystem(dim=" + self.dimension.to_s + ")"

  -> inspect
    to_s
