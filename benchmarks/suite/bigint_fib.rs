use std::time::Instant;

// Minimal big unsigned integer: base-2^32, little-endian
struct Big {
    d: Vec<u32>,
}

impl Big {
    fn from_u32(n: u32) -> Big {
        Big { d: vec![n] }
    }

    fn add(&self, other: &Big) -> Big {
        let len = self.d.len().max(other.d.len());
        let mut result = Vec::with_capacity(len + 1);
        let mut carry: u64 = 0;
        for i in 0..len {
            let a = if i < self.d.len() { self.d[i] as u64 } else { 0 };
            let b = if i < other.d.len() { other.d[i] as u64 } else { 0 };
            let s = a + b + carry;
            result.push(s as u32);
            carry = s >> 32;
        }
        if carry > 0 {
            result.push(carry as u32);
        }
        Big { d: result }
    }

    fn is_zero(&self) -> bool {
        self.d.iter().all(|&x| x == 0)
    }

    fn digit_count_decimal(&self) -> usize {
        if self.is_zero() {
            return 1;
        }
        // Convert to decimal by repeated division by 10^9
        let mut chunks = Vec::new();
        let mut tmp = self.d.clone();
        loop {
            let mut all_zero = true;
            for &x in &tmp {
                if x != 0 {
                    all_zero = false;
                    break;
                }
            }
            if all_zero {
                break;
            }
            // Divide tmp by 10^9
            let divisor: u64 = 1_000_000_000;
            let mut rem: u64 = 0;
            for i in (0..tmp.len()).rev() {
                let cur = (rem << 32) | tmp[i] as u64;
                tmp[i] = (cur / divisor) as u32;
                rem = cur % divisor;
            }
            // Trim leading zeros
            while tmp.len() > 1 && *tmp.last().unwrap() == 0 {
                tmp.pop();
            }
            chunks.push(rem as u32);
        }
        if chunks.is_empty() {
            return 1;
        }
        // Count digits: all chunks except the last have exactly 9 digits
        let last = chunks[chunks.len() - 1];
        let mut count = (chunks.len() - 1) * 9;
        let mut t = last;
        if t == 0 {
            count += 1;
        } else {
            while t > 0 {
                count += 1;
                t /= 10;
            }
        }
        count
    }
}

fn main() {
    let t0 = Instant::now();

    let mut a = Big::from_u32(0);
    let mut b = Big::from_u32(1);

    for _ in 0..100000 {
        let tmp = b;
        b = a.add(&tmp);
        a = tmp;
    }

    let digits = b.digit_count_decimal();

    let elapsed = t0.elapsed();
    println!("{}", digits);
    println!("elapsed: {:.3}s", elapsed.as_secs_f64());
}
