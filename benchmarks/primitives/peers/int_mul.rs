use std::time::Instant;
fn main(){ let n:i64=300000000; let mut s:u64=1; let t0=Instant::now();
 for _ in 0..n { s=s.wrapping_mul(6364136223846793005).wrapping_add(1); }
 let el=t0.elapsed().as_secs_f64();
 println!("{}\nops: {}\nelapsed: {:.6}s",s,n,el); }
