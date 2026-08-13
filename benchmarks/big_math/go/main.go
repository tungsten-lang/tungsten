// Go math/big lane for `tungsten bench bignum`.
//
// Implements the shared external-harness contract (see rust/src/main.rs and
// odin/main.odin): deterministic xorshift operands, per-cell validation,
// 500us warm-up, pilot calibration, and one
// "external\tgo\t<op>\t<limbs>\t<iterations>\t<ns>" row per size.
//
// math/big exposes a mutable API, so like the GMP and Odin lanes this
// harness alternates two result destinations; the stdlib has no LCM, so the
// lcm lane times the idiomatic composition (a / gcd(a,b)) * b.
package main

import (
	"fmt"
	"math"
	"math/big"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	powExponent   = 5
	seedA         = 0x243f6a8885a308d3
	seedB         = 0x13198a2e03707344
	powmodMSeed   = 0xa4093822299f31d0
	maxIterations = 40_000_000
	pilotMinNs    = 20_000.0
	warmDuration  = 500 * time.Microsecond
	shiftBits     = 13
)

var supportedOperations = []string{
	"add", "sub", "mul", "sqr", "div", "mod", "gcd",
	"and", "or", "xor", "shl", "shr", "cmp", "neg", "abs",
	"pow", "powmod", "lcm", "isqrt", "tostr", "fromstr",
	"add1", "sub1", "mul1", "div1",
}

// Asymmetric "big op small" rows: the second operand is one 64-bit limb.
// math/big has no unsigned-word entry points, so the honest Go form is the
// ordinary Int/Int method with a pre-built one-limb operand.
func isWordRow(operation string) bool {
	switch operation {
	case "add1", "sub1", "mul1", "div1":
		return true
	}
	return false
}

var benchSink uint64

func xorshiftWord(state *uint64) uint64 {
	x := *state
	x ^= x >> 12
	x ^= x << 25
	x ^= x >> 27
	*state = x
	return x * 2685821657736338717
}

func operandBytes(limbs int, seed uint64) []byte {
	buffer := make([]byte, limbs*8)
	state := seed
	for limb := 0; limb < limbs; limb++ {
		word := xorshiftWord(&state)
		for index := 0; index < 8; index++ {
			buffer[limb*8+index] = byte(word >> (8 * index))
		}
	}
	buffer[0] |= 1
	buffer[len(buffer)-1] |= 0x80
	return buffer
}

func fromLittleEndian(buffer []byte) *big.Int {
	bigEndian := make([]byte, len(buffer))
	for index, value := range buffer {
		bigEndian[len(buffer)-1-index] = value
	}
	return new(big.Int).SetBytes(bigEndian)
}

func operand(limbs int, seed uint64) *big.Int {
	return fromLittleEndian(operandBytes(limbs, seed))
}

type operands struct {
	rowLimbs int
	a        *big.Int
	b        *big.Int
	modulus  *big.Int
	decimal  string
}

func makeOperands(operation string, limbs int) *operands {
	aLimbs := limbs
	if operation == "div" || operation == "mod" || operation == "isqrt" {
		aLimbs = 2 * limbs
	}
	a := operand(aLimbs, seedA^uint64(limbs))
	var b *big.Int
	if operation == "cmp" {
		buffer := operandBytes(aLimbs, seedA^uint64(limbs))
		buffer[0] ^= 1
		b = fromLittleEndian(buffer)
	} else if isWordRow(operation) {
		b = operand(1, seedB^uint64(limbs))
	} else {
		b = operand(limbs, seedB^uint64(limbs))
	}
	modulus := new(big.Int)
	if operation == "powmod" {
		modulus = operand(limbs, powmodMSeed^uint64(limbs))
	}
	if operation == "abs" {
		a.Neg(a)
	}
	decimal := ""
	if operation == "fromstr" {
		decimal = a.Text(10)
	}
	return &operands{rowLimbs: limbs, a: a, b: b, modulus: modulus, decimal: decimal}
}

func touch(value *big.Int, salt uint64) {
	word := salt
	if bits := value.Bits(); len(bits) > 0 {
		word ^= uint64(bits[0])
	}
	benchSink ^= word
}

func runIntResult(operation string, input *operands, r0, r1 *big.Int, iterations int) float64 {
	exponent := big.NewInt(powExponent)
	start := time.Now()
	switch operation {
	case "add", "add1":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Add(input.a, input.b)
			touch(r, uint64(i))
		}
	case "sub", "sub1":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Sub(input.a, input.b)
			touch(r, uint64(i))
		}
	case "mul", "mul1":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Mul(input.a, input.b)
			touch(r, uint64(i))
		}
	case "sqr":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Mul(input.a, input.a)
			touch(r, uint64(i))
		}
	case "div", "div1":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Quo(input.a, input.b)
			touch(r, uint64(i))
		}
	case "mod":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Rem(input.a, input.b)
			touch(r, uint64(i))
		}
	case "gcd":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.GCD(nil, nil, input.a, input.b)
			touch(r, uint64(i))
		}
	case "and":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.And(input.a, input.b)
			touch(r, uint64(i))
		}
	case "or":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Or(input.a, input.b)
			touch(r, uint64(i))
		}
	case "xor":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Xor(input.a, input.b)
			touch(r, uint64(i))
		}
	case "shl":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Lsh(input.a, shiftBits)
			touch(r, uint64(i))
		}
	case "shr":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Rsh(input.a, shiftBits)
			touch(r, uint64(i))
		}
	case "neg":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Neg(input.a)
			touch(r, uint64(i))
		}
	case "abs":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Abs(input.a)
			touch(r, uint64(i))
		}
	case "pow":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Exp(input.a, exponent, nil)
			touch(r, uint64(i))
		}
	case "powmod":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Exp(input.a, input.b, input.modulus)
			touch(r, uint64(i))
		}
	case "lcm":
		// The stdlib has no LCM; time the composition a Go program must
		// write: (a / gcd(a, b)) * b with a fresh temporary per request.
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			g := new(big.Int).GCD(nil, nil, input.a, input.b)
			g.Quo(input.a, g)
			r.Mul(g, input.b)
			touch(r, uint64(i))
		}
	case "isqrt":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.Sqrt(input.a)
			touch(r, uint64(i))
		}
	case "fromstr":
		for i := 0; i < iterations; i++ {
			r := r0
			if i&1 == 1 {
				r = r1
			}
			r.SetString(input.decimal, 10)
			touch(r, uint64(i))
		}
	default:
		panic("unsupported integer-result operation: " + operation)
	}
	return float64(time.Since(start).Nanoseconds()) / float64(iterations)
}

func runCmp(a, b *big.Int, iterations int) float64 {
	start := time.Now()
	for i := 0; i < iterations; i++ {
		benchSink ^= uint64(int64(a.Cmp(b))) ^ uint64(i)
	}
	return float64(time.Since(start).Nanoseconds()) / float64(iterations)
}

func runTostr(a *big.Int, iterations int) float64 {
	start := time.Now()
	for i := 0; i < iterations; i++ {
		// String results are not retained between iterations, matching the
		// native lane's tostr lifecycle.
		text := a.Text(10)
		benchSink ^= uint64(len(text)) ^ uint64(i)
	}
	return float64(time.Since(start).Nanoseconds()) / float64(iterations)
}

func warmIterations(operation string, limbs int) int {
	// Match the native harness's cheap/expensive warm-up granularity; the
	// expensive lanes warm two operations so both alternating destinations
	// hold live capacity before the timed region starts.
	switch {
	case operation == "powmod",
		operation == "isqrt" && limbs >= 4,
		operation == "lcm" && limbs >= 16,
		(operation == "div" || operation == "mod" || operation == "gcd") && limbs >= 128:
		return 2
	case (operation == "mul" || operation == "sqr") && limbs >= 256,
		(operation == "pow" || operation == "tostr" || operation == "fromstr") && limbs >= 64:
		return 8
	}
	return 1024
}

func runOnce(operation string, input *operands, r0, r1 *big.Int, iterations int) float64 {
	switch operation {
	case "cmp":
		return runCmp(input.a, input.b, iterations)
	case "tostr":
		return runTostr(input.a, iterations)
	}
	return runIntResult(operation, input, r0, r1, iterations)
}

func measure(operation string, input *operands, r0, r1 *big.Int, iterations int) float64 {
	warm := warmIterations(operation, input.rowLimbs)
	warmStart := time.Now()
	for {
		runOnce(operation, input, r0, r1, warm)
		if time.Since(warmStart) >= warmDuration {
			break
		}
	}
	return runOnce(operation, input, r0, r1, iterations)
}

func calibrate(operation string, input *operands, r0, r1 *big.Int, targetNs float64) int {
	pilot := 1
	for {
		nsPerOperation := measure(operation, input, r0, r1, pilot)
		if nsPerOperation*float64(pilot) >= pilotMinNs || pilot >= 4096 {
			estimate := math.Floor(targetNs / math.Max(nsPerOperation, 0.001))
			return int(math.Min(math.Max(estimate, 1), maxIterations))
		}
		pilot = min(pilot*16, 4096)
	}
}

func validateCase(operation string, input *operands, limbs int) error {
	expectedABits := 64 * limbs
	if operation == "div" || operation == "mod" || operation == "isqrt" {
		expectedABits = 128 * limbs
	}
	if input.a.BitLen() != expectedABits {
		return fmt.Errorf(
			"operand width mismatch: expected %d bits, got %d",
			expectedABits, input.a.BitLen(),
		)
	}
	expectedBBits := 64 * limbs
	if isWordRow(operation) {
		expectedBBits = 64
	}
	if input.b.BitLen() != expectedBBits && operation != "cmp" {
		return fmt.Errorf(
			"second operand width mismatch: expected %d bits, got %d",
			expectedBBits, input.b.BitLen(),
		)
	}
	invalid := func(detail string) error {
		return fmt.Errorf("%s validation failed: %s", operation, detail)
	}
	t0 := new(big.Int)
	t1 := new(big.Int)
	switch operation {
	case "add", "add1":
		t0.Add(input.a, input.b)
		if t1.Sub(t0, input.b).Cmp(input.a) != 0 {
			return invalid("(a + b) - b != a")
		}
	case "sub", "sub1":
		t0.Sub(input.a, input.b)
		if t1.Add(t0, input.b).Cmp(input.a) != 0 {
			return invalid("(a - b) + b != a")
		}
	case "mul", "mul1":
		t0.Mul(input.a, input.b)
		quotient, remainder := new(big.Int).QuoRem(t0, input.a, new(big.Int))
		if quotient.Cmp(input.b) != 0 || remainder.Sign() != 0 {
			return invalid("product quotient/remainder invariant")
		}
	case "sqr":
		t0.Mul(input.a, input.a)
		if t1.Sqrt(t0).Cmp(input.a) != 0 {
			return invalid("sqrt(a * a) != a")
		}
	case "div", "mod", "div1":
		quotient, remainder := new(big.Int).QuoRem(input.a, input.b, new(big.Int))
		t0.Mul(quotient, input.b).Add(t0, remainder)
		if t0.Cmp(input.a) != 0 || remainder.Sign() < 0 || remainder.Cmp(input.b) >= 0 {
			return invalid("a != (a / b) * b + (a % b)")
		}
	case "gcd":
		t0.GCD(nil, nil, input.a, input.b)
		if t1.Rem(input.a, t0).Sign() != 0 || t1.Rem(input.b, t0).Sign() != 0 {
			return invalid("gcd does not divide both inputs")
		}
	case "and":
		t0.And(input.a, input.b)
		if t1.And(t0, input.a).Cmp(t0) != 0 || t1.And(t0, input.b).Cmp(t0) != 0 {
			return invalid("and result is not a subset of both operands")
		}
	case "or":
		t0.Or(input.a, input.b)
		if t1.Or(t0, input.a).Cmp(t0) != 0 || t1.Or(t0, input.b).Cmp(t0) != 0 {
			return invalid("or result is not a superset of both operands")
		}
	case "xor":
		t0.Xor(input.a, input.b)
		if t1.Xor(t0, input.b).Cmp(input.a) != 0 {
			return invalid("(a xor b) xor b != a")
		}
	case "shl":
		t0.Lsh(input.a, shiftBits)
		if t1.Rsh(t0, shiftBits).Cmp(input.a) != 0 {
			return invalid("(a << 13) >> 13 != a")
		}
	case "shr":
		t0.Rsh(input.a, shiftBits)
		mask := new(big.Int).Sub(new(big.Int).Lsh(big.NewInt(1), shiftBits), big.NewInt(1))
		t1.Lsh(t0, shiftBits).Add(t1, mask.And(mask, input.a))
		if t1.Cmp(input.a) != 0 {
			return invalid("right-shift quotient/remainder invariant")
		}
	case "cmp":
		if input.a.Cmp(input.b) != 1 {
			return invalid("lowest-bit-different operands should have a > b")
		}
	case "neg":
		t0.Neg(input.a)
		if t1.Neg(t0).Cmp(input.a) != 0 {
			return invalid("double negation")
		}
	case "abs":
		t0.Abs(input.a)
		if input.a.Sign() >= 0 || t0.Cmp(t1.Neg(input.a)) != 0 {
			return invalid("abs lane input/result signs")
		}
	case "pow":
		t0.Exp(input.a, big.NewInt(powExponent), nil)
		square := new(big.Int).Mul(input.a, input.a)
		t1.Mul(square, square).Mul(t1, input.a)
		if t0.Cmp(t1) != 0 {
			return invalid("a**5 != (a*a)*(a*a)*a")
		}
	case "powmod":
		t0.Exp(input.a, input.b, input.modulus)
		if input.modulus.BitLen() != 64*limbs || t0.Sign() < 0 || t0.Cmp(input.modulus) >= 0 {
			return invalid("powmod result outside [0, modulus)")
		}
	case "lcm":
		g := new(big.Int).GCD(nil, nil, input.a, input.b)
		t0.Quo(input.a, g).Mul(t0, input.b)
		if t1.Mul(t0, g).Cmp(new(big.Int).Mul(input.a, input.b)) != 0 || t0.Sign() < 0 {
			return invalid("lcm(a,b) * gcd(a,b) != a*b")
		}
	case "isqrt":
		t0.Sqrt(input.a)
		next := new(big.Int).Add(t0, big.NewInt(1))
		if t1.Mul(t0, t0).Cmp(input.a) > 0 || next.Mul(next, next).Cmp(input.a) <= 0 {
			return invalid("sqrt floor bounds")
		}
	case "tostr":
		text := input.a.Text(10)
		if _, ok := t0.SetString(text, 10); !ok || t0.Cmp(input.a) != 0 {
			return invalid("decimal output does not round-trip")
		}
	case "fromstr":
		if _, ok := t0.SetString(input.decimal, 10); !ok || t0.Cmp(input.a) != 0 {
			return invalid("decimal input does not round-trip")
		}
	default:
		return fmt.Errorf("unknown operation: %s", operation)
	}
	return nil
}

func runSweep(operation, sizeCSV string, runs int, targetMs float64) error {
	supported := false
	for _, candidate := range supportedOperations {
		if operation == candidate {
			supported = true
		}
	}
	if !supported {
		return fmt.Errorf("unknown operation: %s", operation)
	}
	if runs <= 0 || math.IsNaN(targetMs) || math.IsInf(targetMs, 0) || targetMs <= 0 {
		return fmt.Errorf("runs and target-ms must be positive")
	}
	targetNs := targetMs * 1e6
	for _, piece := range strings.Split(sizeCSV, ",") {
		limbs, err := strconv.Atoi(piece)
		if err != nil || limbs < 1 || limbs > 16384 {
			return fmt.Errorf("limb count outside 1..16384: %s", piece)
		}
		input := makeOperands(operation, limbs)
		if err := validateCase(operation, input, limbs); err != nil {
			return err
		}
		r0 := new(big.Int)
		r1 := new(big.Int)
		iterations := calibrate(operation, input, r0, r1, targetNs)
		best := math.Inf(1)
		for run := 0; run < runs; run++ {
			best = math.Min(best, measure(operation, input, r0, r1, iterations))
		}
		fmt.Printf("external\tgo\t%s\t%d\t%d\t%.3f\n", operation, limbs, iterations, best)
	}
	return nil
}

func runSelfTest() error {
	const (
		decimalA = "123456789012345678901234567890"
		decimalB = "9876543210987654321"
		decimalM = "18446744073709551557"
	)
	expected := map[string]string{
		"add": "123456789022222222112222222211",
		"sub": "123456789002469135690246913569",
		"mul": "1219326311370217952249657064223746380111126352690",
		"sqr": "15241578753238836750495351562536198787501905199875019052100",
		"div": "12499999886",
		"mod": "925925941327160484",
		"gcd": "9",
		"and": "9300074690673838224",
		"or":  "123456789012922147421548383987",
		"xor": "123456789003622072730874545763",
		"shl": "1011358015589135801558913580154880",
		"shr": "15070408814983603381498360",
		"neg": "-123456789012345678901234567890",
		"abs": decimalA,
		"pow": "2867971861733704037813816270841549639248697656451325047518479" +
			"0028886798337811616713594453748240629383657483209495862454267363852838672048294900000",
		"powmod": "15615546817603933683",
		"lcm":    "135480701263357550249961896024860708901236261410",
		"isqrt":  "351364182882014",
	}
	a, _ := new(big.Int).SetString(decimalA, 10)
	b, _ := new(big.Int).SetString(decimalB, 10)
	m, _ := new(big.Int).SetString(decimalM, 10)
	check := func(label, actual string) error {
		if want := expected[label]; actual != want {
			return fmt.Errorf("self-test %s: expected %s, got %s", label, want, actual)
		}
		return nil
	}
	// Pin the shared xorshift/import contract before checking arithmetic.
	if got := operand(1, seedA^1).Text(10); got != "10535676081691261443" {
		return fmt.Errorf("self-test operand1: got %s", got)
	}
	if got := operand(2, seedA^2).Text(10); got != "277571816122073303554693665492320838317" {
		return fmt.Errorf("self-test operand2: got %s", got)
	}
	r := new(big.Int)
	g := new(big.Int)
	steps := []struct {
		label string
		text  func() string
	}{
		{"add", func() string { return r.Add(a, b).Text(10) }},
		{"sub", func() string { return r.Sub(a, b).Text(10) }},
		{"mul", func() string { return r.Mul(a, b).Text(10) }},
		{"sqr", func() string { return r.Mul(a, a).Text(10) }},
		{"div", func() string { return r.Quo(a, b).Text(10) }},
		{"mod", func() string { return r.Rem(a, b).Text(10) }},
		{"gcd", func() string { return r.GCD(nil, nil, a, b).Text(10) }},
		{"and", func() string { return r.And(a, b).Text(10) }},
		{"or", func() string { return r.Or(a, b).Text(10) }},
		{"xor", func() string { return r.Xor(a, b).Text(10) }},
		{"shl", func() string { return r.Lsh(a, shiftBits).Text(10) }},
		{"shr", func() string { return r.Rsh(a, shiftBits).Text(10) }},
		{"neg", func() string { return r.Neg(a).Text(10) }},
		{"abs", func() string { return r.Abs(new(big.Int).Neg(a)).Text(10) }},
		{"pow", func() string { return r.Exp(a, big.NewInt(powExponent), nil).Text(10) }},
		{"powmod", func() string { return r.Exp(a, b, m).Text(10) }},
		{"lcm", func() string {
			g.GCD(nil, nil, a, b)
			g.Quo(a, g)
			return r.Mul(g, b).Text(10)
		}},
		{"isqrt", func() string { return r.Sqrt(a).Text(10) }},
	}
	for _, step := range steps {
		if err := check(step.label, step.text()); err != nil {
			return err
		}
	}
	if a.Cmp(b) != 1 {
		return fmt.Errorf("self-test cmp: expected 1, got %d", a.Cmp(b))
	}
	if text := a.Text(10); text != decimalA {
		return fmt.Errorf("self-test tostr: expected %s, got %s", decimalA, text)
	}
	if _, ok := r.SetString(decimalA, 10); !ok || r.Cmp(a) != 0 {
		return fmt.Errorf("self-test fromstr: decimal input does not round-trip")
	}
	return nil
}

func main() {
	args := os.Args
	if len(args) == 2 && args[1] == "--self-test" {
		if err := runSelfTest(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Println("Go bignum self-test: 22/22 passed")
		return
	}
	if len(args) != 6 || args[1] != "--sweep" {
		fmt.Fprintln(os.Stderr, "usage: bench_big_math_go --self-test | --sweep OP CSV_SIZES RUNS TARGET_MS")
		os.Exit(2)
	}
	runs, runsErr := strconv.Atoi(args[4])
	targetMs, targetErr := strconv.ParseFloat(args[5], 64)
	if runsErr != nil || targetErr != nil {
		fmt.Fprintln(os.Stderr, "invalid runs or target-ms")
		os.Exit(2)
	}
	if err := runSweep(args[2], args[3], runs, targetMs); err != nil {
		fmt.Fprintf(os.Stderr, "tungsten Go bignum benchmark: %v\n", err)
		os.Exit(1)
	}
	if benchSink == 0xdeadbeefdeadbeef {
		fmt.Println("")
	}
}
