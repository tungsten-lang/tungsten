use std::time::Instant;
fn main(){ let t0=Instant::now(); let n=400000; let mut s=String::with_capacity(64);
  for _ in 0..n { s.push_str("abcdefghijklmnopqrstuvwxyz"); }
  let el=t0.elapsed().as_secs_f64(); println!("{}",s.len()); println!("elapsed: {:.6}s",el); }
