package main

// Sequential element write over a fixed [1024] stack array, nested reps times.
// The loop-carried chk + final read-back keep the stores alive. Mirrors
// array_set.w.
import "core:fmt"
import "core:time"
import "core:os"

main :: proc() {
	reps := i64(976562) + i64(len(os.args)) - 1
	tab: [1024]i64
	t0 := time.tick_now()
	chk := reps
	for r: i64 = 0; r < reps; r += 1 {
		for k: i64 = 0; k < 1024; k += 1 {
			tab[k] = chk ~ k
			chk += 1
		}
	}
	el := time.duration_seconds(time.tick_since(t0))
	out := chk ~ tab[0] ~ tab[1023]
	ops := reps * 1024
	fmt.printf("%d\nops: %d\nelapsed: %.6fs\n", out, ops, el)
}
