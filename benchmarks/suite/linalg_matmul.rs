// rustc -O single-file GEMM (no ndarray). Labelled naive vs BLAS peers.
use std::time::Instant;

fn main() {
    let n: usize = 512;
    let k_iters = 8;
    let nn = n * n;
    let mut a = vec![0.0f32; nn];
    let mut b = vec![0.0f32; nn];
    let mut c = vec![0.0f32; nn];
    for i in 0..nn {
        a[i] = ((i as i64 * 31 + 7).rem_euclid(17) as f32) / 17.0;
        b[i] = ((i as i64 * 13 + 3).rem_euclid(19) as f32) / 19.0;
    }
    matmul(&a, &b, &mut c, n);
    let t0 = Instant::now();
    for _ in 0..k_iters {
        matmul(&a, &b, &mut c, n);
    }
    let elapsed = t0.elapsed().as_secs_f64();
    println!("{}", (c[0] * 1_000_000.0) as i32);
    println!("elapsed: {}s", elapsed);
}

fn matmul(a: &[f32], b: &[f32], c: &mut [f32], n: usize) {
    for i in 0..n {
        for j in 0..n {
            let mut acc = 0.0f32;
            for k in 0..n {
                acc += a[i * n + k] * b[k * n + j];
            }
            c[i * n + j] = acc;
        }
    }
}
