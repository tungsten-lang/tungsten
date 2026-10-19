use num_bigint::{BigInt, Sign};
use num_integer::Integer;
use num_traits::{Signed, Zero};
use std::cmp::Ordering;
use std::env;
use std::hint::black_box;
use std::io::{self, Write};
use std::process::ExitCode;
use std::time::{Duration, Instant};

const MASK64: u64 = u64::MAX;
const POW_EXPONENT: u32 = 5;
const POWMOD_M_SEED: u64 = 0xa409_3822_299f_31d0;
const MAX_ITERATIONS: usize = 40_000_000;
const PILOT_MIN_TIME: Duration = Duration::from_micros(20);
const WARM_TIME: Duration = Duration::from_micros(500);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Operation {
    Add,
    Sub,
    Mul,
    Sqr,
    Div,
    Mod,
    Gcd,
    And,
    Or,
    Xor,
    Shl,
    Shr,
    Cmp,
    Neg,
    Abs,
    Pow,
    Powmod,
    Lcm,
    Isqrt,
    Tostr,
    Fromstr,
    Add1,
    Sub1,
    Mul1,
    Div1,
    Mod1,
    Not,
    Tdiv,
    Tmod,
    Cdiv,
    Cmod,
    Divexact,
    Divisible,
    Iroot,
    Psquare,
    Invmod,
    Bitlen,
    Popcnt,
    Hamdist,
    Scan1,
    Scan0,
    Tstbit,
    Setbit,
    Clrbit,
    Combit,
    Cmpabs,
}

impl Operation {
    fn parse(name: &str) -> Result<Self, String> {
        match name {
            "add" => Ok(Self::Add),
            "sub" => Ok(Self::Sub),
            "mul" => Ok(Self::Mul),
            "sqr" => Ok(Self::Sqr),
            "div" => Ok(Self::Div),
            "mod" => Ok(Self::Mod),
            "gcd" => Ok(Self::Gcd),
            "and" => Ok(Self::And),
            "or" => Ok(Self::Or),
            "xor" => Ok(Self::Xor),
            "shl" => Ok(Self::Shl),
            "shr" => Ok(Self::Shr),
            "cmp" => Ok(Self::Cmp),
            "neg" => Ok(Self::Neg),
            "abs" => Ok(Self::Abs),
            "pow" => Ok(Self::Pow),
            "powmod" => Ok(Self::Powmod),
            "lcm" => Ok(Self::Lcm),
            "isqrt" => Ok(Self::Isqrt),
            "tostr" => Ok(Self::Tostr),
            "fromstr" => Ok(Self::Fromstr),
            "add1" => Ok(Self::Add1),
            "sub1" => Ok(Self::Sub1),
            "mul1" => Ok(Self::Mul1),
            "div1" => Ok(Self::Div1),
            "mod1" => Ok(Self::Mod1),
            "not" => Ok(Self::Not),
            "tdiv" => Ok(Self::Tdiv),
            "tmod" => Ok(Self::Tmod),
            "cdiv" => Ok(Self::Cdiv),
            "cmod" => Ok(Self::Cmod),
            "divexact" => Ok(Self::Divexact),
            "divisible" => Ok(Self::Divisible),
            "iroot" => Ok(Self::Iroot),
            "psquare" => Ok(Self::Psquare),
            "invmod" => Ok(Self::Invmod),
            "bitlen" => Ok(Self::Bitlen),
            "popcnt" => Ok(Self::Popcnt),
            "hamdist" => Ok(Self::Hamdist),
            "scan1" => Ok(Self::Scan1),
            "scan0" => Ok(Self::Scan0),
            "tstbit" => Ok(Self::Tstbit),
            "setbit" => Ok(Self::Setbit),
            "clrbit" => Ok(Self::Clrbit),
            "combit" => Ok(Self::Combit),
            "cmpabs" => Ok(Self::Cmpabs),
            _ => Err(format!("unknown operation: {name}")),
        }
    }

    /// Asymmetric "big op small" rows: the second operand is one limb, and
    /// the lane times num-bigint's u64 scalar operators.
    fn is_word_row(self) -> bool {
        matches!(
            self,
            Self::Add1 | Self::Sub1 | Self::Mul1 | Self::Div1 | Self::Mod1
        )
    }
}

struct Operands {
    row_limbs: usize,
    a: BigInt,
    b: BigInt,
    word: u64,
    modulus: BigInt,
    decimal: String,
}

fn xorshift_word(state: &mut u64) -> u64 {
    let mut x = *state & MASK64;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    x.wrapping_mul(2_685_821_657_736_338_717)
}

fn operand(limbs: usize, seed: u64) -> BigInt {
    let mut bytes = vec![0_u8; limbs * 8];
    let mut state = seed;
    for chunk in bytes.chunks_exact_mut(8) {
        chunk.copy_from_slice(&xorshift_word(&mut state).to_le_bytes());
    }
    bytes[0] |= 1;
    *bytes.last_mut().expect("operand has at least one limb") |= 0x80;
    BigInt::from_bytes_le(Sign::Plus, &bytes)
}

fn operands(operation: Operation, limbs: usize) -> Operands {
    let a_limbs = match operation {
        Operation::Div
        | Operation::Mod
        | Operation::Isqrt
        | Operation::Tdiv
        | Operation::Tmod
        | Operation::Cdiv
        | Operation::Cmod
        | Operation::Divisible
        | Operation::Psquare => 2 * limbs,
        _ => limbs,
    };
    let mut a = operand(a_limbs, 0x243f_6a88_85a3_08d3 ^ limbs as u64);
    let mut b = if matches!(operation, Operation::Cmp | Operation::Cmpabs) {
        &a ^ BigInt::from(1_u8)
    } else if operation.is_word_row() {
        operand(1, 0x1319_8a2e_0370_7344 ^ limbs as u64)
    } else {
        operand(limbs, 0x1319_8a2e_0370_7344 ^ limbs as u64)
    };
    if operation == Operation::Divexact {
        a = &a * &b;
    } else if operation == Operation::Invmod {
        let one = BigInt::from(1_u8);
        while a.gcd(&b) != one {
            b += 2_u8;
        }
    } else if operation == Operation::Setbit {
        a.set_bit(13, false);
    }
    let word = low_u64(&b);
    if operation == Operation::Abs {
        a = -a;
    }
    let modulus = if operation == Operation::Powmod {
        operand(limbs, POWMOD_M_SEED ^ limbs as u64)
    } else {
        BigInt::zero()
    };
    let decimal = if operation == Operation::Fromstr {
        a.to_str_radix(10)
    } else {
        String::new()
    };
    Operands {
        row_limbs: limbs,
        a,
        b,
        word,
        modulus,
        decimal,
    }
}

fn low_u64(value: &BigInt) -> u64 {
    value.iter_u64_digits().next().unwrap_or(0)
}

/*
 * Keep one prior immutable result live until after its successor has been
 * computed. This mirrors the Tungsten/Python contract without giving Rust an
 * owned-operand or AddAssign path that could mutate an input buffer in place.
 */
#[inline(never)]
fn bench_bigint<F>(input: &Operands, iterations: usize, apply: F) -> (Duration, u64)
where
    F: Fn(&BigInt, &BigInt, &BigInt, &str, u64) -> BigInt,
{
    let mut previous: Option<BigInt> = None;
    let mut sink = 0_u64;
    let start = Instant::now();
    for index in 0..iterations {
        let result = apply(
            black_box(&input.a),
            black_box(&input.b),
            black_box(&input.modulus),
            black_box(input.decimal.as_str()),
            black_box(input.word),
        );
        // This use occurs after `apply`, so the prior allocation cannot be
        // released early and reused while the next result is being formed.
        black_box(&previous);
        sink ^= low_u64(&result).wrapping_add(index as u64);
        previous = Some(result);
    }
    let elapsed = start.elapsed();
    black_box(&previous);
    black_box(sink);
    (elapsed, sink)
}

#[inline(never)]
fn bench_u64<F>(input: &Operands, iterations: usize, apply: F) -> (Duration, u64)
where
    F: Fn(&BigInt, &BigInt) -> u64,
{
    let mut sink = 0_u64;
    let start = Instant::now();
    for index in 0..iterations {
        let code = apply(black_box(&input.a), black_box(&input.b));
        sink ^= code.wrapping_add(index as u64);
    }
    let elapsed = start.elapsed();
    black_box(sink);
    (elapsed, sink)
}

#[inline(never)]
fn bench_cmp(input: &Operands, iterations: usize) -> (Duration, u64) {
    let mut sink = 0_u64;
    let start = Instant::now();
    for index in 0..iterations {
        let ordering = black_box(&input.a).cmp(black_box(&input.b));
        let code = match ordering {
            Ordering::Less => u64::MAX,
            Ordering::Equal => 0,
            Ordering::Greater => 1,
        };
        sink ^= code.wrapping_add(index as u64);
    }
    let elapsed = start.elapsed();
    black_box(sink);
    (elapsed, sink)
}

#[inline(never)]
fn bench_cmpabs(input: &Operands, iterations: usize) -> (Duration, u64) {
    let mut sink = 0_u64;
    let start = Instant::now();
    for index in 0..iterations {
        let ordering = black_box(&input.a)
            .magnitude()
            .cmp(black_box(&input.b).magnitude());
        let code = match ordering {
            Ordering::Less => u64::MAX,
            Ordering::Equal => 0,
            Ordering::Greater => 1,
        };
        sink ^= code.wrapping_add(index as u64);
    }
    let elapsed = start.elapsed();
    black_box(sink);
    (elapsed, sink)
}

#[inline(never)]
fn bench_tostr(input: &Operands, iterations: usize) -> (Duration, u64) {
    let mut sink = 0_u64;
    let start = Instant::now();
    for index in 0..iterations {
        let text = black_box(&input.a).to_str_radix(10);
        sink ^= (text.len() as u64).wrapping_add(index as u64);
        black_box(&text);
        // Unlike BigInt results, string results are not retained by the
        // native lane, so `text` is intentionally dropped each iteration.
    }
    let elapsed = start.elapsed();
    black_box(sink);
    (elapsed, sink)
}

fn measure(operation: Operation, input: &Operands, iterations: usize) -> (Duration, u64) {
    match operation {
        Operation::Add => bench_bigint(input, iterations, |a, b, _, _, _| a + b),
        Operation::Sub => bench_bigint(input, iterations, |a, b, _, _, _| a - b),
        Operation::Mul => bench_bigint(input, iterations, |a, b, _, _, _| a * b),
        Operation::Sqr => bench_bigint(input, iterations, |a, _, _, _, _| a * a),
        Operation::Div | Operation::Tdiv | Operation::Divexact => {
            bench_bigint(input, iterations, |a, b, _, _, _| a / b)
        }
        Operation::Mod | Operation::Tmod => {
            bench_bigint(input, iterations, |a, b, _, _, _| a % b)
        }
        Operation::Cdiv => bench_bigint(input, iterations, |a, b, _, _, _| a.div_ceil(b)),
        Operation::Cmod => bench_bigint(input, iterations, |a, b, _, _, _| {
            let r = a % b;
            if r.is_zero() { r } else { r - b }
        }),
        Operation::Divisible => {
            bench_u64(input, iterations, |a, b| u64::from(a.is_multiple_of(b)))
        }
        Operation::Gcd => bench_bigint(input, iterations, |a, b, _, _, _| a.gcd(b)),
        Operation::And => bench_bigint(input, iterations, |a, b, _, _, _| a & b),
        Operation::Or => bench_bigint(input, iterations, |a, b, _, _, _| a | b),
        Operation::Xor => bench_bigint(input, iterations, |a, b, _, _, _| a ^ b),
        Operation::Not => bench_bigint(input, iterations, |a, _, _, _, _| !a),
        Operation::Shl => bench_bigint(input, iterations, |a, _, _, _, _| a << 13_usize),
        Operation::Shr => bench_bigint(input, iterations, |a, _, _, _, _| a >> 13_usize),
        Operation::Cmp => bench_cmp(input, iterations),
        Operation::Cmpabs => bench_cmpabs(input, iterations),
        Operation::Neg => bench_bigint(input, iterations, |a, _, _, _, _| -a),
        Operation::Abs => bench_bigint(input, iterations, |a, _, _, _, _| a.abs()),
        Operation::Pow => bench_bigint(input, iterations, |a, _, _, _, _| a.pow(POW_EXPONENT)),
        Operation::Powmod => {
            bench_bigint(input, iterations, |a, b, modulus, _, _| a.modpow(b, modulus))
        }
        Operation::Invmod => bench_bigint(input, iterations, |a, b, _, _, _| {
            a.modinv(b).expect("coprime benchmark operands")
        }),
        Operation::Lcm => bench_bigint(input, iterations, |a, b, _, _, _| a.lcm(b)),
        Operation::Isqrt => bench_bigint(input, iterations, |a, _, _, _, _| a.sqrt()),
        Operation::Iroot => bench_bigint(input, iterations, |a, _, _, _, _| a.cbrt()),
        Operation::Psquare => bench_u64(input, iterations, |a, _| {
            let s = a.sqrt();
            u64::from(&s * &s == *a)
        }),
        Operation::Bitlen => bench_u64(input, iterations, |a, _| a.bits()),
        Operation::Popcnt => bench_u64(input, iterations, |a, _| a.magnitude().count_ones()),
        Operation::Hamdist => {
            bench_u64(input, iterations, |a, b| (a ^ b).magnitude().count_ones())
        }
        Operation::Scan1 => {
            bench_u64(input, iterations, |a, _| a.trailing_zeros().unwrap_or(u64::MAX))
        }
        Operation::Scan0 => {
            bench_u64(input, iterations, |a, _| a.magnitude().trailing_ones())
        }
        Operation::Tstbit => bench_u64(input, iterations, |a, _| u64::from(a.bit(13))),
        Operation::Setbit => bench_bigint(input, iterations, |a, _, _, _, _| {
            let mut r = a.clone();
            r.set_bit(13, true);
            r
        }),
        Operation::Clrbit => bench_bigint(input, iterations, |a, _, _, _, _| {
            let mut r = a.clone();
            r.set_bit(0, false);
            r
        }),
        Operation::Combit => bench_bigint(input, iterations, |a, _, _, _, _| {
            let mut r = a.clone();
            r.set_bit(13, !r.bit(13));
            r
        }),
        Operation::Tostr => bench_tostr(input, iterations),
        Operation::Fromstr => bench_bigint(input, iterations, |_, _, _, decimal, _| {
            BigInt::parse_bytes(decimal.as_bytes(), 10).expect("valid benchmark decimal")
        }),
        Operation::Add1 => bench_bigint(input, iterations, |a, _, _, _, word| a + word),
        Operation::Sub1 => bench_bigint(input, iterations, |a, _, _, _, word| a - word),
        Operation::Mul1 => bench_bigint(input, iterations, |a, _, _, _, word| a * word),
        Operation::Div1 => bench_bigint(input, iterations, |a, _, _, _, word| a / word),
        Operation::Mod1 => bench_bigint(input, iterations, |a, _, _, _, word| a % word),
    }
}

fn validate_case(operation: Operation, input: &Operands, limbs: usize) -> Result<(), String> {
    let expected_a_bits = match operation {
        Operation::Div
        | Operation::Mod
        | Operation::Isqrt
        | Operation::Tdiv
        | Operation::Tmod
        | Operation::Cdiv
        | Operation::Cmod
        | Operation::Divisible
        | Operation::Psquare => 128 * limbs,
        _ => 64 * limbs,
    };
    if operation != Operation::Divexact && input.a.bits() as usize != expected_a_bits {
        return Err(format!(
            "operand width mismatch: expected {expected_a_bits} bits, got {}",
            input.a.bits()
        ));
    }
    let expected_b_bits = if operation.is_word_row() { 64 } else { 64 * limbs };
    if !matches!(operation, Operation::Cmp | Operation::Cmpabs | Operation::Invmod)
        && input.b.bits() as usize != expected_b_bits
    {
        return Err(format!(
            "second operand width mismatch: expected {expected_b_bits} bits, got {}",
            input.b.bits()
        ));
    }
    if operation.is_word_row() && BigInt::from(input.word) != input.b {
        return Err("hoisted word does not match the one-limb operand".to_owned());
    }
    Ok(())
}

fn warmed_sample(operation: Operation, input: &Operands, iterations: usize) -> f64 {
    let warm_chunk = match operation {
        Operation::Powmod | Operation::Invmod => 1,
        Operation::Isqrt | Operation::Iroot if input.row_limbs >= 4 => 1,
        Operation::Lcm if input.row_limbs >= 16 => 1,
        Operation::Div
        | Operation::Mod
        | Operation::Tdiv
        | Operation::Tmod
        | Operation::Cdiv
        | Operation::Cmod
        | Operation::Divexact
        | Operation::Divisible
        | Operation::Gcd if input.row_limbs >= 128 => 1,
        Operation::Mul | Operation::Sqr if input.row_limbs >= 256 => 8,
        Operation::Pow | Operation::Tostr | Operation::Fromstr if input.row_limbs >= 64 => 8,
        _ => 1_024,
    };
    let warm_start = Instant::now();
    loop {
        let (_, sink) = measure(operation, input, warm_chunk);
        black_box(sink);
        if warm_start.elapsed() >= WARM_TIME {
            break;
        }
    }
    let (elapsed, sink) = measure(operation, input, iterations);
    black_box(sink);
    elapsed.as_secs_f64() * 1.0e9 / iterations as f64
}

fn calibrate(operation: Operation, input: &Operands, target_ns: f64) -> usize {
    let mut pilot = 1_usize;
    loop {
        let ns_per_operation = warmed_sample(operation, input, pilot);
        let elapsed = Duration::from_secs_f64(ns_per_operation * pilot as f64 / 1.0e9);
        if elapsed >= PILOT_MIN_TIME || pilot >= 4_096 {
            let estimate = (target_ns / ns_per_operation.max(0.001)).floor();
            return estimate.clamp(1.0, MAX_ITERATIONS as f64) as usize;
        }
        pilot = (pilot * 16).min(4_096);
    }
}

fn run_sweep(
    operation_name: &str,
    size_csv: &str,
    runs: usize,
    target_ms: f64,
) -> Result<(), String> {
    let operation = Operation::parse(operation_name)?;
    if runs == 0 || !target_ms.is_finite() || target_ms <= 0.0 {
        return Err("runs and target-ms must be positive".to_owned());
    }
    let sizes = size_csv
        .split(',')
        .map(|piece| {
            piece
                .parse::<usize>()
                .map_err(|_| format!("invalid limb count: {piece}"))
                .and_then(|size| {
                    if (1..=16_384).contains(&size) {
                        Ok(size)
                    } else {
                        Err(format!("limb count outside 1..16384: {size}"))
                    }
                })
        })
        .collect::<Result<Vec<_>, _>>()?;
    if sizes.is_empty() {
        return Err("size list must not be empty".to_owned());
    }

    let target_ns = target_ms * 1.0e6;
    for limbs in sizes {
        let input = operands(operation, limbs);
        validate_case(operation, &input, limbs)?;
        let iterations = calibrate(operation, &input, target_ns);
        let mut best = f64::INFINITY;
        for _ in 0..runs {
            best = best.min(warmed_sample(operation, &input, iterations));
        }
        println!("external\trust\t{operation_name}\t{limbs}\t{iterations}\t{best:.3}");
        io::stdout()
            .flush()
            .map_err(|error| format!("could not flush benchmark row: {error}"))?;
    }
    Ok(())
}

fn real_main() -> Result<(), String> {
    let args = env::args().collect::<Vec<_>>();
    if args.len() != 6 || args[1] != "--sweep" {
        return Err(format!(
            "usage: {} --sweep OP CSV_SIZES RUNS TARGET_MS",
            args.first()
                .map(String::as_str)
                .unwrap_or("rust-bignum-bench")
        ));
    }
    let runs = args[4]
        .parse::<usize>()
        .map_err(|_| format!("invalid run count: {}", args[4]))?;
    let target_ms = args[5]
        .parse::<f64>()
        .map_err(|_| format!("invalid target-ms: {}", args[5]))?;
    run_sweep(&args[2], &args[3], runs, target_ms)
}

fn main() -> ExitCode {
    match real_main() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("tungsten Rust bignum benchmark: {error}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn operand_generation_matches_the_native_contract() {
        assert_eq!(
            operand(1, 0x243f_6a88_85a3_08d3 ^ 1).to_str_radix(16),
            "92363d936dc97a03"
        );
        assert_eq!(
            operand(2, 0x243f_6a88_85a3_08d3 ^ 2).to_str_radix(16),
            "d0d263221410f540ffc586254582e2ad"
        );
    }

    #[test]
    fn every_operation_validates_and_executes() {
        let names = [
            "add", "sub", "mul", "sqr", "div", "mod", "gcd", "and", "or", "xor", "shl", "shr",
            "cmp", "neg", "abs", "pow", "powmod", "lcm", "isqrt", "tostr", "fromstr", "add1",
            "sub1", "mul1", "div1",
        ];
        for name in names {
            let operation = Operation::parse(name).unwrap();
            let input = operands(operation, 1);
            validate_case(operation, &input, 1).unwrap();
            let (_, sink) = measure(operation, &input, 1);
            black_box(sink);
        }
    }
}
