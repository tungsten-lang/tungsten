use std::time::Instant;
// Sequential element read over a fixed [1024] stack array, nested reps times.
// `tab[k]+r` varies each outer pass so the reduction can't be shortcut. Mirrors
// array_get.w.
fn main(){ let reps:i64=std::hint::black_box(976562); let mut tab=[0i64;1024];
 for j in 0..1024 { tab[j]=(j as i64).wrapping_mul(2654435761).wrapping_add(reps); }
 let t0=Instant::now();
 let mut chk:i64=reps;
 for r in 0..reps { for k in 0..1024 { chk^=tab[k].wrapping_add(r); } }
 let el=t0.elapsed().as_secs_f64();
 let ops=reps*1024;
 println!("{}\nops: {}\nelapsed: {:.6}s",chk,ops,el); }
