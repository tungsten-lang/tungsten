package main

import "base:intrinsics"
import "core:fmt"
import "core:math"
import big "core:math/big"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

POW_EXPONENT :: 5
POWMOD_M_SEED :: u64(0xa4093822299f31d0)
MAX_ITERATIONS :: 50_000_000
WARM_DURATION_NS :: 500_000

SUPPORTED_OPERATIONS :: [?]string {
	"add", "sub", "mul", "sqr", "div", "mod", "gcd",
	"and", "or", "xor", "shl", "shr", "cmp", "neg", "abs",
	"pow", "powmod", "lcm", "isqrt", "tostr", "fromstr",
	"add1", "sub1", "mul1", "div1",
}

// Asymmetric "big op small" rows: the second operand is one 64-bit limb.
// The value lives in [2^63, 2^64), which does not fit core:math/big's
// DIGIT, so the honest Odin form is the ordinary Int/Int procedure with a
// one-limb operand rather than the *_digit entries.
is_word_row :: proc(operation: string) -> bool {
	return operation == "add1" || operation == "sub1" ||
	       operation == "mul1" || operation == "div1"
}

bench_sink: u64

must :: #force_inline proc(err: big.Error) {
	if err != nil {
		panic("core:math/big operation failed")
	}
}

is_supported_operation :: proc(operation: string) -> bool {
	for candidate in SUPPORTED_OPERATIONS {
		if operation == candidate { return true }
	}
	return false
}

xorshift_word :: #force_inline proc(state: ^u64) -> u64 {
	x := state^
	x ~= x >> 12
	x ~= x << 25
	x ~= x >> 27
	state^ = x
	return x * 2685821657736338717
}

operand_bytes :: proc(limbs: int, seed: u64) -> []u8 {
	bytes := make([]u8, limbs * 8)
	state := seed
	for limb in 0..<limbs {
		word := xorshift_word(&state)
		for byte in 0..<8 {
			bytes[limb * 8 + byte] = u8(word >> u64(byte * 8))
		}
	}
	bytes[0] |= 1
	bytes[len(bytes) - 1] |= 0x80
	return bytes
}

set_operand :: proc(value: ^big.Int, limbs: int, seed: u64) {
	bytes := operand_bytes(limbs, seed)
	defer delete(bytes)
	must(big.int_from_bytes_little(value, bytes))
}

touch :: #force_inline proc(value: ^big.Int, salt: u64) {
	word := salt
	if value.used > 0 {
		word ~= u64(value.digit[0])
	}
	old := intrinsics.volatile_load(&bench_sink)
	intrinsics.volatile_store(&bench_sink, old ~ word)
}

run_int_result :: proc(operation: string, a, b, modulus, r0, r1: ^big.Int, iterations: int) -> f64 {
	start := time.now()
	switch operation {
	case "add", "add1":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.add(r, a, b)); touch(r, u64(i))
		}
	case "sub", "sub1":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.sub(r, a, b)); touch(r, u64(i))
		}
	case "mul", "mul1":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.mul(r, a, b)); touch(r, u64(i))
		}
	case "sqr":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.sqr(r, a)); touch(r, u64(i))
		}
	case "div", "div1":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.div(r, a, b)); touch(r, u64(i))
		}
	case "mod":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.mod(r, a, b)); touch(r, u64(i))
		}
	case "gcd":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.gcd(r, a, b)); touch(r, u64(i))
		}
	case "and":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.bit_and(r, a, b)); touch(r, u64(i))
		}
	case "or":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.bit_or(r, a, b)); touch(r, u64(i))
		}
	case "xor":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.bit_xor(r, a, b)); touch(r, u64(i))
		}
	case "shl":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.shl(r, a, 13)); touch(r, u64(i))
		}
	case "shr":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.shr(r, a, 13)); touch(r, u64(i))
		}
	case "neg":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.neg(r, a)); touch(r, u64(i))
		}
	case "abs":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.abs(r, a)); touch(r, u64(i))
		}
	case "pow":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.pow(r, a, POW_EXPONENT)); touch(r, u64(i))
		}
	case "powmod":
		// Odin ships its Montgomery/sliding-window implementation under the
		// internal_* API rather than the friendly public procedure map.
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.internal_int_power_modulo(r, a, b, modulus)); touch(r, u64(i))
		}
	case "lcm":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.lcm(r, a, b)); touch(r, u64(i))
		}
	case "isqrt":
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.sqrt(r, a)); touch(r, u64(i))
		}
	case "fromstr":
		text, err := big.itoa(a, 10)
		must(err)
		defer delete(text)
		for i in 0..<iterations {
			r := r0 if i & 1 == 0 else r1
			must(big.atoi(r, text, 10)); touch(r, u64(i))
		}
	case:
		panic("unsupported integer-result operation")
	}
	elapsed := time.duration_nanoseconds(time.since(start))
	return f64(elapsed) / f64(iterations)
}

run_cmp :: proc(a, b: ^big.Int, iterations: int) -> f64 {
	a_slot := a
	b_slot := b
	start := time.now()
	for i in 0..<iterations {
		// Force both invariant operands through volatile pointer loads.  The
		// comparison differs only in the lowest bit, and without this barrier
		// LLVM can hoist its full-scan result out of the timed loop.
		aa := intrinsics.volatile_load(&a_slot)
		bb := intrinsics.volatile_load(&b_slot)
		comparison, err := big.cmp(aa, bb)
		must(err)
		old := intrinsics.volatile_load(&bench_sink)
		intrinsics.volatile_store(&bench_sink, old ~ u64(i64(comparison)) ~ u64(i))
	}
	elapsed := time.duration_nanoseconds(time.since(start))
	return f64(elapsed) / f64(iterations)
}

run_tostr :: proc(a: ^big.Int, iterations: int) -> f64 {
	start := time.now()
	for i in 0..<iterations {
		text, err := big.itoa(a, 10)
		must(err)
		old := intrinsics.volatile_load(&bench_sink)
		intrinsics.volatile_store(&bench_sink, old ~ u64(len(text)) ~ u64(i))
		// The native tostr lane releases each string immediately; unlike
		// BigInt result lanes, it does not retain a prior string generation.
		delete(text)
	}
	elapsed := time.duration_nanoseconds(time.since(start))
	return f64(elapsed) / f64(iterations)
}

warm_iterations :: proc(operation: string, limbs: int) -> int {
	// Match the native harness's cheap/expensive warm-up granularity while
	// always priming both alternating result destinations when both are used.
	count := 1024
	if operation == "powmod" ||
	   (operation == "isqrt" && limbs >= 4) ||
	   (operation == "lcm" && limbs >= 16) ||
	   ((operation == "div" || operation == "mod" || operation == "gcd") && limbs >= 128) {
		count = 1
	} else if ((operation == "mul" || operation == "sqr") && limbs >= 256) ||
	          ((operation == "pow" || operation == "tostr" || operation == "fromstr") && limbs >= 64) {
		count = 8
	}
	if count == 1 {
		// Integer-result lanes alternate r0/r1.  Two warm operations both
		// reserve capacity and leave r1 live while timed iteration zero writes
		// r0.  This preserves the one-prior-result-live contract even when the
		// calibrated timed region itself contains only one expensive operation.
		return 2
	}
	return count
}

measure :: proc(operation: string, limbs, iterations: int) -> f64 {
	a, b, modulus, r0, r1: big.Int
	defer big.destroy(&a, &b, &modulus, &r0, &r1)
	a_limbs := limbs
	if operation == "div" || operation == "mod" || operation == "isqrt" {
		a_limbs = limbs * 2
	}
	set_operand(&a, a_limbs, 0x243f6a8885a308d3 ~ u64(limbs))
	if operation == "cmp" {
		bytes := operand_bytes(a_limbs, 0x243f6a8885a308d3 ~ u64(limbs))
		bytes[0] ~= 1
		must(big.int_from_bytes_little(&b, bytes))
		delete(bytes)
	} else {
		b_limbs := 1 if is_word_row(operation) else limbs
		set_operand(&b, b_limbs, 0x13198a2e03707344 ~ u64(limbs))
	}
	must(big.set(&modulus, 0))
	if operation == "powmod" {
		set_operand(&modulus, limbs, POWMOD_M_SEED ~ u64(limbs))
	}
	if operation == "abs" {
		must(big.neg(&a, &a))
	}

	must(big.set(&r0, 0))
	must(big.set(&r1, 0))
	warm := warm_iterations(operation, limbs)
	warm_start := time.now()

	if operation == "cmp" {
		for {
			_ = run_cmp(&a, &b, warm)
			if time.duration_nanoseconds(time.since(warm_start)) >= WARM_DURATION_NS { break }
		}
		return run_cmp(&a, &b, iterations)
	}
	if operation == "tostr" {
		for {
			_ = run_tostr(&a, warm)
			if time.duration_nanoseconds(time.since(warm_start)) >= WARM_DURATION_NS { break }
		}
		return run_tostr(&a, iterations)
	}
	for {
		_ = run_int_result(operation, &a, &b, &modulus, &r0, &r1, warm)
		if time.duration_nanoseconds(time.since(warm_start)) >= WARM_DURATION_NS { break }
	}
	return run_int_result(operation, &a, &b, &modulus, &r0, &r1, iterations)
}

calibrate :: proc(operation: string, limbs: int, target_ns: f64) -> int {
	iterations := 1
	for _ in 0..<10 {
		ns_per_operation := measure(operation, limbs, iterations)
		elapsed := ns_per_operation * f64(iterations)
		if elapsed >= target_ns * 0.55 {
			estimate := int(f64(iterations) * target_ns / max(elapsed, 1.0) + 0.5)
			return min(MAX_ITERATIONS, max(1, estimate))
		}
		scale := min(100.0, max(2.0, target_ns / max(elapsed, 1.0)))
		iterations = min(MAX_ITERATIONS, max(iterations + 1, int(f64(iterations) * scale)))
	}
	return iterations
}

benchmark :: proc(operation: string, limbs, runs: int, target_ms: f64) {
	target_ns := target_ms * 1e6
	iterations := calibrate(operation, limbs, target_ns)
	best := max(f64)
	for _ in 0..<runs {
		ns := measure(operation, limbs, iterations)
		best = min(best, ns)
	}
	fmt.printfln("external\todin\t%s\t%d\t%d\t%.9f", operation, limbs, iterations, best)
}

self_test_decimal :: proc(label: string, value: ^big.Int, expected: string) -> bool {
	actual, err := big.itoa(value, 10)
	if err != nil {
		fmt.eprintfln("self-test %s: conversion failed (%v)", label, err)
		return false
	}
	defer delete(actual)
	if actual != expected {
		fmt.eprintfln("self-test %s: expected %s, got %s", label, expected, actual)
		return false
	}
	return true
}

run_self_test :: proc() -> bool {
	A :: "123456789012345678901234567890"
	B :: "9876543210987654321"
	M :: "18446744073709551557"

	a, b, modulus, negative_a, result, generated: big.Int
	defer big.destroy(&a, &b, &modulus, &negative_a, &result, &generated)
	must(big.atoi(&a, A, 10))
	must(big.atoi(&b, B, 10))
	must(big.atoi(&modulus, M, 10))
	must(big.neg(&negative_a, &a))
	must(big.set(&result, 0))

	passed := true
	check := proc(label: string, value: ^big.Int, expected: string, passed: ^bool) {
		if !self_test_decimal(label, value, expected) { passed^ = false }
	}

	// Pin the shared xorshift/import contract before checking arithmetic.
	set_operand(&generated, 1, 0x243f6a8885a308d3 ~ 1)
	check("operand1", &generated, "10535676081691261443", &passed)
	set_operand(&generated, 2, 0x243f6a8885a308d3 ~ 2)
	check("operand2", &generated, "277571816122073303554693665492320838317", &passed)

	must(big.add(&result, &a, &b))
	check("add", &result, "123456789022222222112222222211", &passed)
	must(big.sub(&result, &a, &b))
	check("sub", &result, "123456789002469135690246913569", &passed)
	must(big.mul(&result, &a, &b))
	check("mul", &result, "1219326311370217952249657064223746380111126352690", &passed)
	must(big.sqr(&result, &a))
	check("sqr", &result, "15241578753238836750495351562536198787501905199875019052100", &passed)
	must(big.div(&result, &a, &b))
	check("div", &result, "12499999886", &passed)
	must(big.mod(&result, &a, &b))
	check("mod", &result, "925925941327160484", &passed)
	must(big.gcd(&result, &a, &b))
	check("gcd", &result, "9", &passed)
	must(big.bit_and(&result, &a, &b))
	check("and", &result, "9300074690673838224", &passed)
	must(big.bit_or(&result, &a, &b))
	check("or", &result, "123456789012922147421548383987", &passed)
	must(big.bit_xor(&result, &a, &b))
	check("xor", &result, "123456789003622072730874545763", &passed)
	must(big.shl(&result, &a, 13))
	check("shl", &result, "1011358015589135801558913580154880", &passed)
	must(big.shr(&result, &a, 13))
	check("shr", &result, "15070408814983603381498360", &passed)

	comparison, compare_err := big.cmp(&a, &b)
	must(compare_err)
	if comparison != 1 {
		fmt.eprintfln("self-test cmp: expected 1, got %d", comparison)
		passed = false
	}
	must(big.neg(&result, &a))
	check("neg", &result, "-123456789012345678901234567890", &passed)
	must(big.abs(&result, &negative_a))
	check("abs", &result, A, &passed)
	must(big.pow(&result, &a, POW_EXPONENT))
	check(
		"pow",
		&result,
		"28679718617337040378138162708415496392486976564513250475184790028886798337811616713594453748240629383657483209495862454267363852838672048294900000",
		&passed,
	)
	must(big.internal_int_power_modulo(&result, &a, &b, &modulus))
	check("powmod", &result, "15615546817603933683", &passed)
	must(big.lcm(&result, &a, &b))
	check("lcm", &result, "135480701263357550249961896024860708901236261410", &passed)
	must(big.sqrt(&result, &a))
	check("isqrt", &result, "351364182882014", &passed)

	text, text_err := big.itoa(&a, 10)
	must(text_err)
	if text != A {
		fmt.eprintfln("self-test tostr: expected %s, got %s", A, text)
		passed = false
	}
	delete(text)
	must(big.atoi(&result, A, 10))
	check("fromstr", &result, A, &passed)
	return passed
}

main :: proc() {
	if len(os.args) == 2 && os.args[1] == "--self-test" {
		if !run_self_test() {
			os.exit(1)
		}
		fmt.println("Odin bignum self-test: 23/23 passed")
		return
	}
	if len(os.args) != 6 || os.args[1] != "--sweep" {
		fmt.eprintln("usage: bench_big_math_odin --self-test | --sweep OP CSV_SIZES RUNS TARGET_MS")
		os.exit(2)
	}
	operation := os.args[2]
	if !is_supported_operation(operation) {
		fmt.eprintfln("unknown operation: %s", operation)
		os.exit(2)
	}
	runs, runs_ok := strconv.parse_int(os.args[4])
	target_ms, target_ok := strconv.parse_f64(os.args[5])
	if !runs_ok || runs <= 0 || !target_ok || target_ms <= 0 || math.is_nan(target_ms) || math.is_inf(target_ms) {
		fmt.eprintln("invalid runs or target-ms")
		os.exit(2)
	}
	sizes := os.args[3]
	for size_text in strings.split_by_byte_iterator(&sizes, ',') {
		limbs, ok := strconv.parse_int(size_text)
		if !ok || limbs <= 0 || limbs > 16_384 {
			fmt.eprintln("invalid limb count")
			os.exit(2)
		}
		benchmark(operation, limbs, runs, target_ms)
	}
	if intrinsics.volatile_load(&bench_sink) == 0xdeadbeefdeadbeef {
		fmt.println("")
	}
}
