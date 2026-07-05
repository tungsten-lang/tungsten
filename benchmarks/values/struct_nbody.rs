use std::time::Instant;

const PI: f64 = 3.141592653589793;
const SOLAR_MASS: f64 = 4.0 * PI * PI;
const DAYS_PER_YEAR: f64 = 365.24;
const N_BODIES: usize = 5;

struct Body {
    x: f64, y: f64, z: f64,
    vx: f64, vy: f64, vz: f64,
    mass: f64,
}

fn advance(bodies: &mut [Body], dt: f64) {
    for i in 0..N_BODIES {
        for j in (i + 1)..N_BODIES {
            let dx = bodies[i].x - bodies[j].x;
            let dy = bodies[i].y - bodies[j].y;
            let dz = bodies[i].z - bodies[j].z;
            let dist = (dx * dx + dy * dy + dz * dz).sqrt();
            let mag = dt / (dist * dist * dist);
            let mj = bodies[j].mass;
            let mi = bodies[i].mass;
            bodies[i].vx -= dx * mj * mag;
            bodies[i].vy -= dy * mj * mag;
            bodies[i].vz -= dz * mj * mag;
            bodies[j].vx += dx * mi * mag;
            bodies[j].vy += dy * mi * mag;
            bodies[j].vz += dz * mi * mag;
        }
    }
    for i in 0..N_BODIES {
        bodies[i].x += dt * bodies[i].vx;
        bodies[i].y += dt * bodies[i].vy;
        bodies[i].z += dt * bodies[i].vz;
    }
}

fn energy(bodies: &[Body]) -> f64 {
    let mut e = 0.0;
    for i in 0..N_BODIES {
        e += 0.5 * bodies[i].mass *
            (bodies[i].vx * bodies[i].vx +
             bodies[i].vy * bodies[i].vy +
             bodies[i].vz * bodies[i].vz);
        for j in (i + 1)..N_BODIES {
            let dx = bodies[i].x - bodies[j].x;
            let dy = bodies[i].y - bodies[j].y;
            let dz = bodies[i].z - bodies[j].z;
            let dist = (dx * dx + dy * dy + dz * dz).sqrt();
            e -= bodies[i].mass * bodies[j].mass / dist;
        }
    }
    e
}

fn offset_momentum(bodies: &mut [Body]) {
    let mut px = 0.0;
    let mut py = 0.0;
    let mut pz = 0.0;
    for i in 0..N_BODIES {
        px += bodies[i].vx * bodies[i].mass;
        py += bodies[i].vy * bodies[i].mass;
        pz += bodies[i].vz * bodies[i].mass;
    }
    bodies[0].vx = -px / SOLAR_MASS;
    bodies[0].vy = -py / SOLAR_MASS;
    bodies[0].vz = -pz / SOLAR_MASS;
}

fn main() {
    let t0 = Instant::now();

    let mut bodies = [
        // Sun
        Body { x: 0.0, y: 0.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0, mass: SOLAR_MASS },
        // Jupiter
        Body { x: 4.84143144246472090e+00, y: -1.16032004402742839e+00, z: -1.03622044471123109e-01,
               vx: 1.66007664274403694e-03 * DAYS_PER_YEAR,
               vy: 7.69901118419740425e-03 * DAYS_PER_YEAR,
               vz: -6.90460016972063023e-05 * DAYS_PER_YEAR,
               mass: 9.54791938424326609e-04 * SOLAR_MASS },
        // Saturn
        Body { x: 8.34336671824457987e+00, y: 4.12479856412430479e+00, z: -4.03523417114321381e-01,
               vx: -2.76742510726862411e-03 * DAYS_PER_YEAR,
               vy: 4.99852801234917238e-03 * DAYS_PER_YEAR,
               vz: 2.30417297573763929e-05 * DAYS_PER_YEAR,
               mass: 2.85885980666130812e-04 * SOLAR_MASS },
        // Uranus
        Body { x: 1.28943695621391310e+01, y: -1.51111514016986312e+01, z: -2.23307578892655734e-01,
               vx: 2.96460137564761618e-03 * DAYS_PER_YEAR,
               vy: 2.37847173959480950e-03 * DAYS_PER_YEAR,
               vz: -2.96589568540237556e-05 * DAYS_PER_YEAR,
               mass: 4.36624404335156298e-05 * SOLAR_MASS },
        // Neptune
        Body { x: 1.53796971148509165e+01, y: -2.59193146099879641e+01, z: 1.79258772950371181e-01,
               vx: 2.68067772490389322e-03 * DAYS_PER_YEAR,
               vy: 1.62824170038242295e-03 * DAYS_PER_YEAR,
               vz: -9.51592254519715870e-05 * DAYS_PER_YEAR,
               mass: 5.15138902046611451e-05 * SOLAR_MASS },
    ];

    offset_momentum(&mut bodies);

    let steps = 500_000;
    let dt = 0.01;
    for _ in 0..steps {
        advance(&mut bodies, dt);
    }

    let e = energy(&bodies);

    let elapsed = t0.elapsed();
    println!("energy: {:.9}", e);
    println!("elapsed: {:.3}s", elapsed.as_secs_f64());
}
