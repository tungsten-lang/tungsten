use std::time::Instant;
// Sequential element write over a fixed [1024] stack array, nested reps times.
// The loop-carried chk + final read-back keep the stores alive. Mirrors
// array_set.w.
fn main(){ let reps:i64=std::hint::black_box(976562); let mut tab=[0i64;1024];
 let t0=Instant::now();
 let mut chk:i64=reps;
 for _r in 0..reps { for k in 0..1024 { tab[k]=chk^(k as i64); chk=chk.wrapping_add(1); } }
 let el=t0.elapsed().as_secs_f64();
 let out=chk^tab[0]^tab[1023];
 let ops=reps*1024;
 println!("{}\nops: {}\nelapsed: {:.6}s",out,ops,el); }
