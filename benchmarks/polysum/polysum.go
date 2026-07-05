// Polynomial ranged-sum benchmark — multi-term polynomials (Go, fixed u64).
//
// IMPORTANT: Go has no built-in big integers in the hot path. These sums
// exceed 2^64 almost immediately (x^7 / x^20 overflow at once), so this
// computes everything MOD 2^64 — the printed values are WRONG. It exists
// only as a native-loop SPEED reference.
//
// N/REPS from argv (defaults 1000000/100).
package main

import (
	"fmt"
	"os"
	"strconv"
)

func ipow(base uint64, e int) uint64 {
	r := uint64(1)
	for i := 0; i < e; i++ {
		r *= base // wraps mod 2^64
	}
	return r
}

func main() {
	var n uint64 = 1000000
	reps := 100
	if len(os.Args) > 1 {
		n, _ = strconv.ParseUint(os.Args[1], 10, 64)
	}
	if len(os.Args) > 2 {
		reps, _ = strconv.Atoi(os.Args[2])
	}

	var t1, t2, t3, t7, t20 uint64
	for r := uint64(0); r < uint64(reps); r++ {
		lo, hi := 1+r, n+r
		for x := lo; x <= hi; x++ {
			t1 += 2*x + 3
			t2 += 5*ipow(x, 2) - 3*x + 1
			t3 += 4*ipow(x, 3) - 2*ipow(x, 2) + 7*x - 5
			t7 += 92*ipow(x, 7) + 13*ipow(x, 3) - 5*x + 8
			t20 += ipow(x, 20) + 17*ipow(x, 13) - 4*ipow(x, 5) + 2*x + 9
		}
	}
	fmt.Printf("%d\n%d\n%d\n%d\n%d\n", t1, t2, t3, t7, t20)
}
