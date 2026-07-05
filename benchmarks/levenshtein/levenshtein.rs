fn levenshtein(s: &[u8], t: &[u8]) -> usize {
    let (m, n) = (s.len(), t.len());
    if m == 0 {
        return n;
    }
    if n == 0 {
        return m;
    }

    let mut prev: Vec<usize> = (0..=n).collect();
    let mut curr: Vec<usize> = vec![0; n + 1];

    for i in 0..m {
        curr[0] = i + 1;
        for j in 0..n {
            let cost = if s[i] == t[j] { 0 } else { 1 };
            let ins = curr[j] + 1;
            let del = prev[j + 1] + 1;
            let sub = prev[j] + cost;
            curr[j + 1] = ins.min(del).min(sub);
        }
        std::mem::swap(&mut prev, &mut curr);
    }

    prev[n]
}

fn main() {
    let s = "the quick brown fox jumps over the lazy dog".repeat(20);
    let t = "the slow brown fox leaps over the lazy cat".repeat(20);
    println!("{}", levenshtein(s.as_bytes(), t.as_bytes()));
}
