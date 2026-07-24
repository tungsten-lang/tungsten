use std::time::Instant;
fn main(){
  let t0=Instant::now();
  let n:i64=1000000; let rounds:i64=200;
  let mut a=vec![0i64;n as usize];
  let mut chk:i64=0;
  for r in 0..rounds {
    for i in 0..n { a[i as usize]=i.wrapping_mul(2654435761).wrapping_add(r); }
    chk^=a[((r*7)%n) as usize];
  }
  let el=t0.elapsed().as_secs_f64();
  println!("{}",chk); println!("elapsed: {:.6}s",el);
}
