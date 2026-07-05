// Fused map-filter-reduce pipeline benchmark (Go, hand-written loop).
//
// Go has no lazy iterator pipeline in the stdlib idiom, so the honest
// spelling is the explicit loop — a baseline alongside C. Each rep uses
// a shifted range (1+r .. N+r) so the REPS loop isn't loop-invariant.
// N/REPS from argv (defaults 1000000/100).
package main

import (
	"fmt"
	"os"
	"strconv"
)

func main() {
	var n uint64 = 1000000
	reps := 100
	if len(os.Args) > 1 {
		n, _ = strconv.ParseUint(os.Args[1], 10, 64)
	}
	if len(os.Args) > 2 {
		reps, _ = strconv.Atoi(os.Args[2])
	}

	var total uint64
	for r := uint64(0); r < uint64(reps); r++ {
		lo, hi := 1+r, n+r
		for x := lo; x <= hi; x++ {
			if x%2 == 0 {
				total += x * x
			}
		}
	}
	fmt.Println(total)
}
