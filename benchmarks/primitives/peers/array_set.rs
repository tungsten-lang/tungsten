use std::time::Instant;
fn main(){ let n:i64=300000000; let mut chk:i64=0; let mut tab=[0i64;1024];
 let t0=Instant::now();
 for i in 0..n { tab[(i&1023) as usize]=i^chk; chk=chk+1; }
 let el=t0.elapsed().as_secs_f64();
 println!("{}\nops: {}\nelapsed: {:.6}s",chk^tab[0],n,el); }
