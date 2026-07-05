-> add_body(b, x, y, z, vx, vy, vz, mass)
  b.push(x)
  b.push(y)
  b.push(z)
  b.push(vx)
  b.push(vy)
  b.push(vz)
  b.push(mass)

-> build_bodies(solar_mass, days_per_year)
  b = f64[35]
  add_body(b, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, solar_mass)
  add_body(b, ~4.84143144246472090, ~-1.16032004402742839, ~-0.103622044471123109, ~1.66007664274403694e-03 * days_per_year, ~7.69901118419740425e-03 * days_per_year, ~-6.90460016972063023e-05 * days_per_year, ~9.54791938424326609e-04 * solar_mass)
  add_body(b, ~8.34336671824457987, ~4.12479856412430479, ~-0.403523417114321381, ~-2.76742510726862411e-03 * days_per_year, ~4.99852801234917238e-03 * days_per_year, ~2.30417297573763929e-05 * days_per_year, ~2.85885980666130812e-04 * solar_mass)
  add_body(b, ~12.8943695621391310, ~-15.1111514016986312, ~-0.223307578892655734, ~2.96460137564761618e-03 * days_per_year, ~2.37847173959480950e-03 * days_per_year, ~-2.96589568540237556e-05 * days_per_year, ~4.36624404335156298e-05 * solar_mass)
  add_body(b, ~15.3796971148509165, ~-25.9193146099879641, ~0.179258772950371181, ~2.68067772490389322e-03 * days_per_year, ~1.62824170038242295e-03 * days_per_year, ~-9.51592254519715870e-05 * days_per_year, ~5.15138902046611451e-05 * solar_mass)
  b

-> offset_momentum(b, n_bodies, solar_mass)
  px = ~0.0
  py = ~0.0
  pz = ~0.0
  i = 0
  while i < n_bodies
    off = i * 7
    px = px + b[off + 3] * b[off + 6]
    py = py + b[off + 4] * b[off + 6]
    pz = pz + b[off + 5] * b[off + 6]
    i = i + 1
  b[3] = ~0.0 - px / solar_mass
  b[4] = ~0.0 - py / solar_mass
  b[5] = ~0.0 - pz / solar_mass

-> advance(b, n_bodies, dt)
  i = 0
  while i < n_bodies
    j = i + 1
    while j < n_bodies
      oi = i * 7
      oj = j * 7
      dx = b[oi] - b[oj]
      dy = b[oi + 1] - b[oj + 1]
      dz = b[oi + 2] - b[oj + 2]
      dist = (dx * dx + dy * dy + dz * dz).sqrt
      mag = dt / (dist * dist * dist)
      b[oi + 3] = b[oi + 3] - dx * b[oj + 6] * mag
      b[oi + 4] = b[oi + 4] - dy * b[oj + 6] * mag
      b[oi + 5] = b[oi + 5] - dz * b[oj + 6] * mag
      b[oj + 3] = b[oj + 3] + dx * b[oi + 6] * mag
      b[oj + 4] = b[oj + 4] + dy * b[oi + 6] * mag
      b[oj + 5] = b[oj + 5] + dz * b[oi + 6] * mag
      j = j + 1
    i = i + 1

  i = 0
  while i < n_bodies
    off = i * 7
    b[off] = b[off] + dt * b[off + 3]
    b[off + 1] = b[off + 1] + dt * b[off + 4]
    b[off + 2] = b[off + 2] + dt * b[off + 5]
    i = i + 1

-> energy(b, n_bodies)
  e = ~0.0
  i = 0
  while i < n_bodies
    off = i * 7
    e = e + ~0.5 * b[off + 6] * (b[off + 3] * b[off + 3] + b[off + 4] * b[off + 4] + b[off + 5] * b[off + 5])
    j = i + 1
    while j < n_bodies
      oj = j * 7
      dx = b[off] - b[oj]
      dy = b[off + 1] - b[oj + 1]
      dz = b[off + 2] - b[oj + 2]
      dist = (dx * dx + dy * dy + dz * dz).sqrt
      e = e - b[off + 6] * b[oj + 6] / dist
      j = j + 1
    i = i + 1
  e

t0 = clock

pi = ~3.141592653589793
solar_mass = ~4.0 * pi * pi
days_per_year = ~365.24
n_bodies = 5

b = build_bodies(solar_mass, days_per_year)
offset_momentum(b, n_bodies, solar_mass)

steps = 500000
dt = ~0.01

s = 0
while s < steps
  advance(b, n_bodies, dt)
  s = s + 1

e = energy(b, n_bodies)

t1 = clock
<< "energy: [e]"
<< "elapsed: [t1 - t0]s"
