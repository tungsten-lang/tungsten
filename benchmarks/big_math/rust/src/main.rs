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
            _ => Err(format!("unknown operation: {name}")),
        }
    }
}

struct Operands {
    row_limbs: usize,
    a: BigInt,
    b: BigInt,
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
        Operation::Div | Operation::Mod | Operation::Isqrt => 2 * limbs,
        _ => limbs,
    };
    let mut a = operand(a_limbs, 0x243f_6a88_85a3_08d3 ^ limbs as u64);
    let b = if operation == Operation::Cmp {
        &a ^ BigInt::from(1_u8)
    } else {
        operand(limbs, 0x1319_8a2e_0370_7344 ^ limbs as u64)
    };
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
    F: Fn(&BigInt, &BigInt, &BigInt, &str) -> BigInt,
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
        Operation::Add => bench_bigint(input, iterations, |a, b, _, _| a + b),
        Operation::Sub => bench_bigint(input, iterations, |a, b, _, _| a - b),
        Operation::Mul => bench_bigint(input, iterations, |a, b, _, _| a * b),
        Operation::Sqr => bench_bigint(input, iterations, |a, _, _, _| a * a),
        Operation::Div => bench_bigint(input, iterations, |a, b, _, _| a / b),
        Operation::Mod => bench_bigint(input, iterations, |a, b, _, _| a % b),
        Operation::Gcd => bench_bigint(input, iterations, |a, b, _, _| a.gcd(b)),
        Operation::And => bench_bigint(input, iterations, |a, b, _, _| a & b),
        Operation::Or => bench_bigint(input, iterations, |a, b, _, _| a | b),
        Operation::Xor => bench_bigint(input, iterations, |a, b, _, _| a ^ b),
        Operation::Shl => bench_bigint(input, iterations, |a, _, _, _| a << 13_usize),
        Operation::Shr => bench_bigint(input, iterations, |a, _, _, _| a >> 13_usize),
        Operation::Cmp => bench_cmp(input, iterations),
        Operation::Neg => bench_bigint(input, iterations, |a, _, _, _| -a),
        Operation::Abs => bench_bigint(input, iterations, |a, _, _, _| a.abs()),
        Operation::Pow => bench_bigint(input, iterations, |a, _, _, _| a.pow(POW_EXPONENT)),
        Operation::Powmod => {
            bench_bigint(input, iterations, |a, b, modulus, _| a.modpow(b, modulus))
        }
        Operation::Lcm => bench_bigint(input, iterations, |a, b, _, _| a.lcm(b)),
        Operation::Isqrt => bench_bigint(input, iterations, |a, _, _, _| a.sqrt()),
        Operation::Tostr => bench_tostr(input, iterations),
        Operation::Fromstr => bench_bigint(input, iterations, |_, _, _, decimal| {
            BigInt::parse_bytes(decimal.as_bytes(), 10).expect("valid benchmark decimal")
        }),
    }
}

fn validate_case(operation: Operation, input: &Operands, limbs: usize) -> Result<(), String> {
    let expected_a_bits = match operation {
        Operation::Div | Operation::Mod | Operation::Isqrt => 128 * limbs,
        _ => 64 * limbs,
    };
    if input.a.bits() as usize != expected_a_bits {
        return Err(format!(
            "operand width mismatch: expected {expected_a_bits} bits, got {}",
            input.a.bits()
        ));
    }
    if input.b.bits() as usize != 64 * limbs {
        return Err(format!(
            "second operand width mismatch: expected {} bits, got {}",
            64 * limbs,
            input.b.bits()
        ));
    }

    let invalid = |detail: &str| Err(format!("{operation:?} validation failed: {detail}"));
    match operation {
        Operation::Add => {
            let result = &input.a + &input.b;
            if &result - &input.b != input.a {
                return invalid("(a + b) - b != a");
            }
        }
        Operation::Sub => {
            let result = &input.a - &input.b;
            if &result + &input.b != input.a {
                return invalid("(a - b) + b != a");
            }
        }
        Operation::Mul => {
            let result = &input.a * &input.b;
            if &result / &input.a != input.b || &result % &input.a != BigInt::zero() {
                return invalid("product quotient/remainder invariant");
            }
        }
        Operation::Sqr => {
            let result = &input.a * &input.a;
            if result.sqrt() != input.a {
                return invalid("sqrt(a * a) != a");
            }
        }
        Operation::Div | Operation::Mod => {
            let quotient = &input.a / &input.b;
            let remainder = &input.a % &input.b;
            if &quotient * &input.b + &remainder != input.a
                || remainder.is_negative()
                || remainder >= input.b
            {
                return invalid("a != (a / b) * b + (a % b)");
            }
        }
        Operation::Gcd => {
            let result = input.a.gcd(&input.b);
            if &input.a % &result != BigInt::zero() || &input.b % &result != BigInt::zero() {
                return invalid("gcd does not divide both inputs");
            }
        }
        Operation::And => {
            let result = &input.a & &input.b;
            if (&result & &input.a) != result || (&result & &input.b) != result {
                return invalid("and result is not a subset of both operands");
            }
        }
        Operation::Or => {
            let result = &input.a | &input.b;
            if (&result | &input.a) != result || (&result | &input.b) != result {
                return invalid("or result is not a superset of both operands");
            }
        }
        Operation::Xor => {
            let result = &input.a ^ &input.b;
            if (&result ^ &input.b) != input.a {
                return invalid("(a xor b) xor b != a");
            }
        }
        Operation::Shl => {
            let result = &input.a << 13_usize;
            if result >> 13_usize != input.a {
                return invalid("(a << 13) >> 13 != a");
            }
        }
        Operation::Shr => {
            let result = &input.a >> 13_usize;
            let mask = (BigInt::from(1_u8) << 13_usize) - 1_u8;
            if (result << 13_usize) + (&input.a & mask) != input.a {
                return invalid("right-shift quotient/remainder invariant");
            }
        }
        Operation::Cmp => {
            if input.a.cmp(&input.b) != Ordering::Greater {
                return invalid("lowest-bit-different operands should have a > b");
            }
        }
        Operation::Neg => {
            let result = -&input.a;
            if -result != input.a {
                return invalid("double negation");
            }
        }
        Operation::Abs => {
            let result = input.a.abs();
            if !input.a.is_negative() || result != -&input.a {
                return invalid("abs lane input/result signs");
            }
        }
        Operation::Pow => {
            let result = input.a.pow(POW_EXPONENT);
            let square = &input.a * &input.a;
            let fourth = &square * &square;
            if result != fourth * &input.a {
                return invalid("a**5 != (a*a)*(a*a)*a");
            }
        }
        Operation::Powmod => {
            let result = input.a.modpow(&input.b, &input.modulus);
            if input.modulus.bits() as usize != 64 * limbs
                || result.is_negative()
                || result >= input.modulus
            {
                return invalid("powmod result outside [0, modulus)");
            }
        }
        Operation::Lcm => {
            let gcd = input.a.gcd(&input.b);
            let lcm = input.a.lcm(&input.b);
            if lcm.is_negative() || lcm * gcd != (&input.a * &input.b).abs() {
                return invalid("lcm(a,b) * gcd(a,b) != abs(a*b)");
            }
        }
        Operation::Isqrt => {
            let result = input.a.sqrt();
            let next = &result + 1_u8;
            if &result * &result > input.a || &next * &next <= input.a {
                return invalid("sqrt floor bounds");
            }
        }
        Operation::Tostr => {
            let text = input.a.to_str_radix(10);
            if BigInt::parse_bytes(text.as_bytes(), 10).as_ref() != Some(&input.a) {
                return invalid("decimal output does not round-trip");
            }
        }
        Operation::Fromstr => {
            if BigInt::parse_bytes(input.decimal.as_bytes(), 10).as_ref() != Some(&input.a) {
                return invalid("decimal input does not round-trip");
            }
        }
    }
    Ok(())
}

fn warmed_sample(operation: Operation, input: &Operands, iterations: usize) -> f64 {
    let warm_chunk = match operation {
        Operation::Powmod => 1,
        Operation::Isqrt if input.row_limbs >= 4 => 1,
        Operation::Lcm if input.row_limbs >= 16 => 1,
        Operation::Div | Operation::Mod | Operation::Gcd if input.row_limbs >= 128 => 1,
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
            "cmp", "neg", "abs", "pow", "powmod", "lcm", "isqrt", "tostr", "fromstr",
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
