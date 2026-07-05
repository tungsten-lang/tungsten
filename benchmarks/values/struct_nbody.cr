t0 = Time.monotonic

PI_VAL = 3.141592653589793
SOLAR_MASS = 4.0 * PI_VAL * PI_VAL
DAYS_PER_YEAR = 365.24

class Body
  property x : Float64
  property y : Float64
  property z : Float64
  property vx : Float64
  property vy : Float64
  property vz : Float64
  property mass : Float64

  def initialize(@x, @y, @z, @vx, @vy, @vz, @mass)
  end
end

def offset_momentum(bodies : Array(Body), solar_mass : Float64)
  px = 0.0
  py = 0.0
  pz = 0.0
  bodies.each do |b|
    px += b.vx * b.mass
    py += b.vy * b.mass
    pz += b.vz * b.mass
  end
  bodies[0].vx = -px / solar_mass
  bodies[0].vy = -py / solar_mass
  bodies[0].vz = -pz / solar_mass
end

def advance(bodies : Array(Body), dt : Float64)
  n = bodies.size
  (0...n).each do |i|
    ((i + 1)...n).each do |j|
      dx = bodies[i].x - bodies[j].x
      dy = bodies[i].y - bodies[j].y
      dz = bodies[i].z - bodies[j].z
      dist = Math.sqrt(dx * dx + dy * dy + dz * dz)
      mag = dt / (dist * dist * dist)
      bodies[i].vx -= dx * bodies[j].mass * mag
      bodies[i].vy -= dy * bodies[j].mass * mag
      bodies[i].vz -= dz * bodies[j].mass * mag
      bodies[j].vx += dx * bodies[i].mass * mag
      bodies[j].vy += dy * bodies[i].mass * mag
      bodies[j].vz += dz * bodies[i].mass * mag
    end
  end
  bodies.each do |b|
    b.x += dt * b.vx
    b.y += dt * b.vy
    b.z += dt * b.vz
  end
end

def energy(bodies : Array(Body)) : Float64
  e = 0.0
  n = bodies.size
  (0...n).each do |i|
    e += 0.5 * bodies[i].mass *
         (bodies[i].vx * bodies[i].vx +
          bodies[i].vy * bodies[i].vy +
          bodies[i].vz * bodies[i].vz)
    ((i + 1)...n).each do |j|
      dx = bodies[i].x - bodies[j].x
      dy = bodies[i].y - bodies[j].y
      dz = bodies[i].z - bodies[j].z
      dist = Math.sqrt(dx * dx + dy * dy + dz * dz)
      e -= bodies[i].mass * bodies[j].mass / dist
    end
  end
  e
end

bodies = [
  # Sun
  Body.new(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SOLAR_MASS),
  # Jupiter
  Body.new(4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
           1.66007664274403694e-03 * DAYS_PER_YEAR,
           7.69901118419740425e-03 * DAYS_PER_YEAR,
           -6.90460016972063023e-05 * DAYS_PER_YEAR,
           9.54791938424326609e-04 * SOLAR_MASS),
  # Saturn
  Body.new(8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
           -2.76742510726862411e-03 * DAYS_PER_YEAR,
           4.99852801234917238e-03 * DAYS_PER_YEAR,
           2.30417297573763929e-05 * DAYS_PER_YEAR,
           2.85885980666130812e-04 * SOLAR_MASS),
  # Uranus
  Body.new(1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
           2.96460137564761618e-03 * DAYS_PER_YEAR,
           2.37847173959480950e-03 * DAYS_PER_YEAR,
           -2.96589568540237556e-05 * DAYS_PER_YEAR,
           4.36624404335156298e-05 * SOLAR_MASS),
  # Neptune
  Body.new(1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
           2.68067772490389322e-03 * DAYS_PER_YEAR,
           1.62824170038242295e-03 * DAYS_PER_YEAR,
           -9.51592254519715870e-05 * DAYS_PER_YEAR,
           5.15138902046611451e-05 * SOLAR_MASS),
]

offset_momentum(bodies, SOLAR_MASS)

steps = 500_000
dt = 0.01
steps.times { advance(bodies, dt) }

e = energy(bodies)

t1 = Time.monotonic
elapsed = (t1 - t0).total_seconds
puts "energy: #{"%.9f" % e}"
puts "elapsed: #{"%.3f" % elapsed}s"
