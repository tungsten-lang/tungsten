use std::time::Instant;

fn main() {
    let t0 = Instant::now();

    let mut total: i64 = 0;
    for py in 0..2000 {
        let ci = -1.5 + py as f64 * 3.0 / 2000.0;
        for px in 0..2000 {
            let cr = -2.0 + px as f64 * 3.0 / 2000.0;
            let mut zr = 0.0_f64;
            let mut zi = 0.0_f64;
            let mut iter: i64 = 0;
            while iter < 50 {
                if zr * zr + zi * zi > 4.0 {
                    break;
                }
                let new_zr = zr * zr - zi * zi + cr;
                zi = 2.0 * zr * zi + ci;
                zr = new_zr;
                iter += 1;
            }
            total += iter;
        }
    }

    let elapsed = t0.elapsed();
    println!("{}", total);
    println!("elapsed: {:.3}s", elapsed.as_secs_f64());
}
