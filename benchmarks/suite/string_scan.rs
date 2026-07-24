use std::time::Instant;

fn main() {
    let t0 = Instant::now();

    let base = "the quick brown fox jumps over the lazy dog ";
    let text = base.repeat(2500000);

    let mut count = 0;
    let mut pos = 0;
    let needle = "fox";
    let needle_len = needle.len();
    while pos <= text.len() - needle_len {
        match text[pos..].find(needle) {
            Some(idx) => {
                count += 1;
                pos += idx + needle_len;
            }
            None => break,
        }
    }

    let elapsed = t0.elapsed();
    println!("{}", count);
    println!("elapsed: {:.3}s", elapsed.as_secs_f64());
}
