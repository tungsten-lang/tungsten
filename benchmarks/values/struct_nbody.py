import time
import math

t0 = time.perf_counter()

PI = 3.141592653589793
SOLAR_MASS = 4.0 * PI * PI
DAYS_PER_YEAR = 365.24

# Bodies: [x, y, z, vx, vy, vz, mass]
bodies = [
    # Sun
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SOLAR_MASS],
    # Jupiter
    [4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
     1.66007664274403694e-03 * DAYS_PER_YEAR,
     7.69901118419740425e-03 * DAYS_PER_YEAR,
     -6.90460016972063023e-05 * DAYS_PER_YEAR,
     9.54791938424326609e-04 * SOLAR_MASS],
    # Saturn
    [8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
     -2.76742510726862411e-03 * DAYS_PER_YEAR,
     4.99852801234917238e-03 * DAYS_PER_YEAR,
     2.30417297573763929e-05 * DAYS_PER_YEAR,
     2.85885980666130812e-04 * SOLAR_MASS],
    # Uranus
    [1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
     2.96460137564761618e-03 * DAYS_PER_YEAR,
     2.37847173959480950e-03 * DAYS_PER_YEAR,
     -2.96589568540237556e-05 * DAYS_PER_YEAR,
     4.36624404335156298e-05 * SOLAR_MASS],
    # Neptune
    [1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
     2.68067772490389322e-03 * DAYS_PER_YEAR,
     1.62824170038242295e-03 * DAYS_PER_YEAR,
     -9.51592254519715870e-05 * DAYS_PER_YEAR,
     5.15138902046611451e-05 * SOLAR_MASS],
]

def offset_momentum(bodies):
    px = py = pz = 0.0
    for b in bodies:
        px += b[3] * b[6]
        py += b[4] * b[6]
        pz += b[5] * b[6]
    bodies[0][3] = -px / SOLAR_MASS
    bodies[0][4] = -py / SOLAR_MASS
    bodies[0][5] = -pz / SOLAR_MASS

def advance(bodies, dt):
    n = len(bodies)
    for i in range(n):
        bi = bodies[i]
        for j in range(i + 1, n):
            bj = bodies[j]
            dx = bi[0] - bj[0]
            dy = bi[1] - bj[1]
            dz = bi[2] - bj[2]
            dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            mag = dt / (dist * dist * dist)
            bi[3] -= dx * bj[6] * mag
            bi[4] -= dy * bj[6] * mag
            bi[5] -= dz * bj[6] * mag
            bj[3] += dx * bi[6] * mag
            bj[4] += dy * bi[6] * mag
            bj[5] += dz * bi[6] * mag
    for b in bodies:
        b[0] += dt * b[3]
        b[1] += dt * b[4]
        b[2] += dt * b[5]

def energy(bodies):
    e = 0.0
    n = len(bodies)
    for i in range(n):
        bi = bodies[i]
        e += 0.5 * bi[6] * (bi[3] * bi[3] + bi[4] * bi[4] + bi[5] * bi[5])
        for j in range(i + 1, n):
            bj = bodies[j]
            dx = bi[0] - bj[0]
            dy = bi[1] - bj[1]
            dz = bi[2] - bj[2]
            dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            e -= bi[6] * bj[6] / dist
    return e

offset_momentum(bodies)

steps = 500_000
dt = 0.01
for _ in range(steps):
    advance(bodies, dt)

e = energy(bodies)

t1 = time.perf_counter()
print(f"energy: {e:.9f}")
print(f"elapsed: {t1 - t0:.3f}s")
