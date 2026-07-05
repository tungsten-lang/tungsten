use std::time::Instant;

fn main() {
    let t0 = Instant::now();

    const N: usize = 2_000_000;
    let mut arr = Vec::with_capacity(N);
    let mut seed: u32 = 42;
    for _ in 0..N {
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) & 0x7FFFFFFF;
        arr.push(seed as i32);
    }

    arr.sort();

    let elapsed = t0.elapsed();
    println!("first={} last={}", arr[0], arr[N - 1]);
    println!("elapsed: {:.3}s", elapsed.as_secs_f64());
}
