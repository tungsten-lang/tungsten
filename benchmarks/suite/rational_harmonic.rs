use std::time::Instant;

// Minimal big unsigned integer: base-2^32, little-endian
#[derive(Clone)]
struct Big {
    d: Vec<u32>,
}

impl Big {
    fn from_u64(mut n: u64) -> Big {
        let mut d = Vec::new();
        if n == 0 {
            d.push(0);
        }
        while n > 0 {
            d.push(n as u32);
            n >>= 32;
        }
        Big { d }
    }

    fn is_zero(&self) -> bool {
        self.d.iter().all(|&x| x == 0)
    }

    fn trim(&mut self) {
        while self.d.len() > 1 && *self.d.last().unwrap() == 0 {
            self.d.pop();
        }
    }

    fn cmp(&self, other: &Big) -> std::cmp::Ordering {
        if self.d.len() != other.d.len() {
            return self.d.len().cmp(&other.d.len());
        }
        for i in (0..self.d.len()).rev() {
            if self.d[i] != other.d[i] {
                return self.d[i].cmp(&other.d[i]);
            }
        }
        std::cmp::Ordering::Equal
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

    fn sub(&self, other: &Big) -> Big {
        let mut result = Vec::with_capacity(self.d.len());
        let mut borrow: i64 = 0;
        for i in 0..self.d.len() {
            let a = self.d[i] as i64;
            let b = if i < other.d.len() { other.d[i] as i64 } else { 0 };
            let mut s = a - b - borrow;
            if s < 0 {
                s += 1i64 << 32;
                borrow = 1;
            } else {
                borrow = 0;
            }
            result.push(s as u32);
        }
        let mut r = Big { d: result };
        r.trim();
        r
    }

    fn mul_u64(&self, b: u64) -> Big {
        if b == 0 {
            return Big::from_u64(0);
        }
        let mut result = Vec::with_capacity(self.d.len() + 2);
        let mut carry: u64 = 0;
        for &digit in &self.d {
            let v = digit as u128 * b as u128 + carry as u128;
            result.push(v as u32);
            carry = (v >> 32) as u64;
        }
        while carry > 0 {
            result.push(carry as u32);
            carry >>= 32;
        }
        if result.is_empty() {
            result.push(0);
        }
        Big { d: result }
    }

    // Division and remainder by a small u64
    fn divmod_u64(&self, b: u64) -> (Big, u64) {
        let mut result = vec![0u32; self.d.len()];
        let mut rem: u128 = 0;
        for i in (0..self.d.len()).rev() {
            rem = (rem << 32) | self.d[i] as u128;
            result[i] = (rem / b as u128) as u32;
            rem %= b as u128;
        }
        let mut r = Big { d: result };
        r.trim();
        (r, rem as u64)
    }

    // General division: returns (quotient, remainder)
    fn divmod(&self, divisor: &Big) -> (Big, Big) {
        use std::cmp::Ordering;
        match self.cmp(divisor) {
            Ordering::Less => return (Big::from_u64(0), self.clone()),
            Ordering::Equal => return (Big::from_u64(1), Big::from_u64(0)),
            _ => {}
        }
        // If divisor fits in u64
        if divisor.d.len() <= 2 {
            let dval = if divisor.d.len() == 1 {
                divisor.d[0] as u64
            } else {
                divisor.d[0] as u64 | ((divisor.d[1] as u64) << 32)
            };
            let (q, r) = self.divmod_u64(dval);
            return (q, Big::from_u64(r));
        }
        // Knuth's Algorithm D (simplified)
        self.long_div(divisor)
    }

    fn long_div(&self, divisor: &Big) -> (Big, Big) {
        let n = divisor.d.len();
        let m = self.d.len() - n;

        // Normalize: shift so top bit of divisor is set
        let shift = divisor.d[n - 1].leading_zeros();
        let u = self.shl_bits(shift);
        let v = divisor.shl_bits(shift);

        let mut q_digits = vec![0u32; m + 1];
        // u has m+n+1 or m+n digits
        let mut rem = Vec::with_capacity(n + 1);
        for i in 0..=n {
            let idx = m + i;
            if idx < u.d.len() {
                rem.push(u.d[idx]);
            } else {
                rem.push(0);
            }
        }

        for j in (0..=m).rev() {
            // Estimate q_hat
            let r_top = if rem.len() > n {
                ((rem[n] as u64) << 32) | rem[n - 1] as u64
            } else {
                rem[n - 1] as u64
            };
            let mut q_hat = r_top / v.d[n - 1] as u64;
            if q_hat > 0xFFFFFFFF {
                q_hat = 0xFFFFFFFF;
            }

            // Multiply and subtract
            loop {
                let product = v.mul_u64(q_hat);
                let rem_big = Big { d: rem.clone() };
                if rem_big.cmp(&product) != std::cmp::Ordering::Less {
                    break;
                }
                q_hat -= 1;
            }

            let product = v.mul_u64(q_hat);
            let rem_big = Big { d: rem.clone() };
            let diff = rem_big.sub(&product);
            rem = diff.d.clone();

            q_digits[j] = q_hat as u32;

            // Bring down next digit
            if j > 0 {
                let bring = if j - 1 < u.d.len() { u.d[j - 1] } else { 0 };
                rem.insert(0, bring);
            }
        }

        let mut q = Big { d: q_digits };
        q.trim();
        // Denormalize remainder
        let mut r = Big { d: rem };
        r.trim();
        if shift > 0 {
            r = r.shr_bits(shift);
        }
        (q, r)
    }

    fn shl_bits(&self, shift: u32) -> Big {
        if shift == 0 {
            return self.clone();
        }
        let mut result = Vec::with_capacity(self.d.len() + 1);
        let mut carry: u32 = 0;
        for &digit in &self.d {
            let v = ((digit as u64) << shift) | carry as u64;
            result.push(v as u32);
            carry = (v >> 32) as u32;
        }
        if carry > 0 {
            result.push(carry);
        }
        Big { d: result }
    }

    fn shr_bits(&self, shift: u32) -> Big {
        if shift == 0 {
            return self.clone();
        }
        let mut result = Vec::with_capacity(self.d.len());
        let mut carry: u32 = 0;
        for i in (0..self.d.len()).rev() {
            let v = ((carry as u64) << 32) | self.d[i] as u64;
            result.push((v >> shift) as u32);
            carry = (v & ((1u64 << shift) - 1)) as u32;
        }
        result.reverse();
        let mut r = Big { d: result };
        r.trim();
        r
    }

    fn digit_count_decimal(&self) -> usize {
        if self.is_zero() {
            return 1;
        }
        // Convert to decimal string and count
        let s = self.to_decimal();
        s.len()
    }

    fn to_decimal(&self) -> String {
        if self.is_zero() {
            return "0".to_string();
        }
        let mut digits = Vec::new();
        let mut tmp = self.clone();
        while !tmp.is_zero() {
            let (q, r) = tmp.divmod_u64(10);
            digits.push((r as u8) + b'0');
            tmp = q;
        }
        digits.reverse();
        String::from_utf8(digits).unwrap()
    }
}

fn gcd(a: &Big, b: &Big) -> Big {
    let mut a = a.clone();
    let mut b = b.clone();
    while !b.is_zero() {
        let (_, r) = a.divmod(&b);
        a = b;
        b = r;
    }
    a
}

fn main() {
    let t0 = Instant::now();

    let mut num = Big::from_u64(0);
    let mut den = Big::from_u64(1);

    for i in 1u64..=3000 {
        // num/den + 1/i = (num*i + den) / (den*i)
        num = num.mul_u64(i);
        num = num.add(&den);
        den = den.mul_u64(i);
        // GCD reduce
        let g = gcd(&num, &den);
        if !g.is_zero() && g.cmp(&Big::from_u64(1)) != std::cmp::Ordering::Equal {
            let (qn, _) = num.divmod(&g);
            let (qd, _) = den.divmod(&g);
            num = qn;
            den = qd;
        }
    }

    let digits = num.digit_count_decimal();

    let elapsed = t0.elapsed();
    println!("{}", digits);
    println!("elapsed: {:.3}s", elapsed.as_secs_f64());
}
