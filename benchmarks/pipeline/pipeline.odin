// Fused map-filter-reduce pipeline benchmark (Odin, hand-written loop).
//
// Like the C / Go / Zig baselines: the optimal eager loop an AOT compiler
// produces. The comparison point for Tungsten's fused `/select/sq:sum`,
// which recognizes the same workload as a closed-form ranged sum.
//
// Each rep uses a SHIFTED range (1+r .. N+r) so the REPS loop is not
// loop-invariant (otherwise the optimizer hoists it). N/REPS come from
// argv (defaults 1_000_000 / 100), matching every other language.
//
// Build: odin build pipeline.odin -file -o:speed && ./pipeline

package main

import "core:fmt"
import "core:os"
import "core:strconv"

main :: proc() {
	n: u64 = 1_000_000
	reps: u64 = 100
	if len(os.args) > 1 {
		n = u64(strconv.atoi(os.args[1]))
	}
	if len(os.args) > 2 {
		reps = u64(strconv.atoi(os.args[2]))
	}

	total: u64 = 0
	for r: u64 = 0; r < reps; r += 1 {
		lo: u64 = 1 + r
		hi: u64 = n + r
		for x: u64 = lo; x <= hi; x += 1 {
			if x % 2 == 0 {
				total += x * x
			}
		}
	}

	fmt.println(total)
}
