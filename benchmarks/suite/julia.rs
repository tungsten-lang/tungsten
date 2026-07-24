use std::time::Instant;

fn main() {
    let t0 = Instant::now();

    let c_re: f64 = -0.7;
    let c_im: f64 = 0.27015;
    let mut total: i64 = 0;
    for py in 0..2000 {
        let zi_init = -1.5 + py as f64 * 3.0 / 2000.0;
        for px in 0..2000 {
            let mut zr = -1.5 + px as f64 * 3.0 / 2000.0;
            let mut zi = zi_init;
            let mut iter: i64 = 0;
            while iter < 50 {
                if zr * zr + zi * zi > 4.0 {
                    break;
                }
                let new_zr = zr * zr - zi * zi + c_re;
                zi = 2.0 * zr * zi + c_im;
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
