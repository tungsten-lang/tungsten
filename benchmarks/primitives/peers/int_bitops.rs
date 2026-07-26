use std::time::Instant;
fn main(){ let n:i64=300000000; let mut s:i64=1; let t0=Instant::now();
 for i in 0..n { s=(s<<13)^(s>>7)^i; }
 let el=t0.elapsed().as_secs_f64();
 println!("{}\nops: {}\nelapsed: {:.6}s",s,n,el); }
