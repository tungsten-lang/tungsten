use std::collections::HashMap;
use std::time::Instant;

fn main() {
    let t0 = Instant::now();

    const NUM_WORDS: usize = 1000;
    const NUM_ITER: usize = 5_000_000;

    let words: Vec<String> = (0..NUM_WORDS).map(|i| format!("word{}", i)).collect();

    let mut freq: HashMap<&str, i32> = HashMap::with_capacity(NUM_WORDS);
    let mut seed: u32 = 42;
    for _ in 0..NUM_ITER {
        seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) & 0x7FFFFFFF;
        let word = &words[(seed as usize) % NUM_WORDS];
        *freq.entry(word.as_str()).or_insert(0) += 1;
    }

    let max_freq = freq.values().max().unwrap();

    let elapsed = t0.elapsed();
    println!("{}", max_freq);
    println!("elapsed: {:.3}s", elapsed.as_secs_f64());
}
