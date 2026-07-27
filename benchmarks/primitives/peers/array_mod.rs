use std::time::Instant;
// Wraparound (masked-index) array read: `tab[i & 1023]` in a flat loop.
// black_box keeps the trip count runtime-unknown (a constant lets LLVM
// restructure by period). Mirrors array_mod.w.
fn main(){ let n:i64=std::hint::black_box(1000000000); let mut chk:i64=0; let mut tab=[0i64;1024];
 for j in 0..1024 { tab[j]=(j as i64).wrapping_mul(2654435761); }
 let t0=Instant::now();
 for i in 0..n { chk^=tab[(i&1023) as usize]; }
 let el=t0.elapsed().as_secs_f64();
 println!("{}\nops: {}\nelapsed: {:.6}s",chk,n,el); }
