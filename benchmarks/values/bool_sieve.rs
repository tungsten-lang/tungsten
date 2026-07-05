use std::time::Instant;

fn main() {
    let t0 = Instant::now();

    let n: usize = 1_000_000;
    let mut is_prime = vec![true; n + 1];
    is_prime[0] = false;
    is_prime[1] = false;

    let mut i: usize = 2;
    while i * i <= n {
        if is_prime[i] {
            let mut j = i * i;
            while j <= n {
                is_prime[j] = false;
                j += i;
            }
        }
        i += 1;
    }

    let mut count: i64 = 0;
    for k in 0..=n {
        if is_prime[k] {
            count += 1;
        }
    }

    let elapsed = t0.elapsed();
    println!("{}", count);
    println!("elapsed: {:.3}s", elapsed.as_secs_f64());
}
