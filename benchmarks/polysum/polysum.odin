// Polynomial ranged-sum benchmark — multi-term polynomials (Odin, fixed u64).
//
// IMPORTANT: overflows 2^64 past degree 2 (x^7/x^20 at once) — values are
// mod 2^64 and therefore WRONG. Native-loop SPEED reference only.
// N/REPS from argv (defaults 1_000_000 / 100).
//
// Build: odin build polysum.odin -file -o:speed && ./polysum

package main

import "core:fmt"
import "core:os"
import "core:strconv"

ipow :: proc(base: u64, e: int) -> u64 {
	r: u64 = 1
	for i := 0; i < e; i += 1 {
		r *= base
	}
	return r
}

main :: proc() {
	n: u64 = 1_000_000
	reps: u64 = 100
	if len(os.args) > 1 {
		n = u64(strconv.atoi(os.args[1]))
	}
	if len(os.args) > 2 {
		reps = u64(strconv.atoi(os.args[2]))
	}

	t1, t2, t3, t7, t20: u64
	for r: u64 = 0; r < reps; r += 1 {
		lo: u64 = 1 + r
		hi: u64 = n + r
		for x: u64 = lo; x <= hi; x += 1 {
			t1 += 2 * x + 3
			t2 += 5 * ipow(x, 2) - 3 * x + 1
			t3 += 4 * ipow(x, 3) - 2 * ipow(x, 2) + 7 * x - 5
			t7 += 92 * ipow(x, 7) + 13 * ipow(x, 3) - 5 * x + 8
			t20 += ipow(x, 20) + 17 * ipow(x, 13) - 4 * ipow(x, 5) + 2 * x + 9
		}
	}

	fmt.printf("%d\n%d\n%d\n%d\n%d\n", t1, t2, t3, t7, t20)
}
