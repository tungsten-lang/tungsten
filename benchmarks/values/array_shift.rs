use std::collections::VecDeque;
use std::time::Instant;

fn main() {
    let t0 = Instant::now();

    const N: usize = 10_000_000;
    let mut a = VecDeque::with_capacity(N);
    for i in 0..N {
        a.push_back((i % 10) as i32);
    }

    let mut b = Vec::with_capacity(N);
    while let Some(v) = a.pop_front() {
        b.push(v);
    }

    let elapsed = t0.elapsed();
    println!("length={} first={} last={}", b.len(), b[0], b[b.len() - 1]);
    println!("elapsed: {:.3}s", elapsed.as_secs_f64());
}
