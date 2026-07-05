//! Rust matmul benchmark with ndarray. Build + run:
//!   cargo run --release -- 256 100
//!
//! ndarray's `dot` calls into BLAS if the `blas` feature is enabled;
//! out of the box it uses a pure-Rust implementation.

use std::env;
use std::time::Instant;
use ndarray::Array2;
use serde_json::json;

fn main() {
    let args: Vec<String> = env::args().collect();
    let n: usize = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(256);
    let k: usize = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(100);

    let mut a_data = vec![0.0f32; n * n];
    let mut b_data = vec![0.0f32; n * n];
    for i in 0..(n * n) {
        a_data[i] = ((i as i64 * 31 + 7).rem_euclid(17) as f32) / 17.0;
        b_data[i] = ((i as i64 * 13 + 3).rem_euclid(19) as f32) / 19.0;
    }
    let a = Array2::from_shape_vec((n, n), a_data).unwrap();
    let b = Array2::from_shape_vec((n, n), b_data).unwrap();

    // Warm up.
    let _ = a.dot(&b);

    let mut times: Vec<f64> = Vec::with_capacity(k);
    for _ in 0..k {
        let t0 = Instant::now();
        let _ = a.dot(&b);
        times.push(t0.elapsed().as_secs_f64() * 1000.0);
    }
    times.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let median_ms = times[k / 2];
    let gflops = (2.0 * (n as f64).powi(3)) / (median_ms * 1e6);

    println!("{}", json!({
        "impl": "rust-ndarray",
        "N": n,
        "K": k,
        "median_ms": (median_ms * 10000.0).round() / 10000.0,
        "gflops": (gflops * 100.0).round() / 100.0,
    }));
}
