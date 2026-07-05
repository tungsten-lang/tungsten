use std::time::Instant;

fn main() {
    let t0 = Instant::now();

    let mut e: f64 = 0.0;
    for _ in 0..100000 {
        e = 0.0;
        let mut factorial: f64 = 1.0;
        for i in 0..=100 {
            e = e + 1.0 / factorial;
            factorial = factorial * (i + 1) as f64;
        }
    }

    let result = (e * 1000000.0) as i64;

    let elapsed = t0.elapsed();
    println!("{}", result);
    println!("elapsed: {:.3}s", elapsed.as_secs_f64());
}
