use std::time::Instant;
fn main(){ let n:i64=20000000; let mut f:f64=0.5; let t0=Instant::now();
 for _ in 0..n { f=3.9*f*(1.0-f); }
 let el=t0.elapsed().as_secs_f64();
 println!("{:.10}\nops: {}\nelapsed: {:.6}s",f,n,el); }
