use std::time::Instant;

fn main() {
    let t0 = Instant::now();

    let n: i64 = 2_000_000;

    let sum: i64 = (0..n)
        .map(|x| x * 3 + 1)
        .filter(|x| x % 2 == 0)
        .map(|x| x / 2)
        .sum();

    let elapsed = t0.elapsed();
    println!("{}", sum);
    println!("elapsed: {:.3}s", elapsed.as_secs_f64());
}
