// Polynomial ranged-sum benchmark — multi-term polynomials (Rust, fixed u64).
//
// IMPORTANT: overflows 2^64 past degree 2 (x^7/x^20 at once). Uses
// std::num::Wrapping so it computes mod 2^64 in both debug and release —
// the printed values are WRONG. Native-loop SPEED reference only.
// N/REPS from argv (defaults 1_000_000 / 100).
//
// Build: rustc -O polysum.rs -o polysum && ./polysum

use std::env;
use std::num::Wrapping;

type W = Wrapping<u64>;

fn ipow(base: W, e: u32) -> W {
    let mut r = Wrapping(1u64);
    for _ in 0..e {
        r *= base;
    }
    r
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let n: u64 = if args.len() > 1 { args[1].parse().unwrap() } else { 1_000_000 };
    let reps: u64 = if args.len() > 2 { args[2].parse().unwrap() } else { 100 };

    let (mut t1, mut t2, mut t3, mut t7, mut t20) =
        (Wrapping(0u64), Wrapping(0u64), Wrapping(0u64), Wrapping(0u64), Wrapping(0u64));
    let c = |k: u64| Wrapping(k);

    for r in 0..reps {
        let (lo, hi) = (1 + r, n + r);
        let mut xi = lo;
        while xi <= hi {
            let x = Wrapping(xi);
            t1 += c(2) * x + c(3);
            t2 += c(5) * ipow(x, 2) - c(3) * x + c(1);
            t3 += c(4) * ipow(x, 3) - c(2) * ipow(x, 2) + c(7) * x - c(5);
            t7 += c(92) * ipow(x, 7) + c(13) * ipow(x, 3) - c(5) * x + c(8);
            t20 += ipow(x, 20) + c(17) * ipow(x, 13) - c(4) * ipow(x, 5) + c(2) * x + c(9);
            xi += 1;
        }
    }

    println!("{}\n{}\n{}\n{}\n{}", t1.0, t2.0, t3.0, t7.0, t20.0);
}
