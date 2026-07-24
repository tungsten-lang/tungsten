use std::time::Instant;

fn main() {
    let t0 = Instant::now();

    let mut sum: i64 = 0;
    for n in 1..=1_000_000i64 {
        let mut x = n;
        let mut steps: i64 = 0;
        while x != 1 {
            if x % 2 == 0 {
                x = x / 2;
            } else {
                x = 3 * x + 1;
            }
            steps += 1;
        }
        sum += steps;
    }

    let elapsed = t0.elapsed();
    println!("{}", sum);
    println!("elapsed: {:.3}s", elapsed.as_secs_f64());
}
