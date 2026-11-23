# A pendulum released from rest. With time in units of sqrt(length/gravity),
# the equation of motion is theta'' = -sin(theta). Angles are in radians.
-> measured_period(amplitude, step)
  theta = amplitude
  speed = ~0.0
  elapsed = ~0.0
  while theta > ~0.0
    # Velocity Verlet, with two half kicks around one drift.
    speed -= step * Math.sin(theta) / 2
    previous = theta
    theta += step * speed
    speed -= step * Math.sin(theta) / 2
    if theta <= ~0.0
      # The first crossing is a quarter cycle. Interpolate inside this step.
      return 4 * (elapsed + step * previous / (previous - theta))
    elapsed += step

pi = Math.acos(~-1.0)
<< "release (deg) | period / small-angle period"
[5, 30, 60, 90, 120, 150].each ->(degrees)
  angle = degrees * pi / 180
  ratio = measured_period(angle, ~0.002) / (2 * pi)
  << "[degrees] | [ratio]"
