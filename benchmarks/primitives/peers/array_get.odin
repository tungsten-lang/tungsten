package main

// Sequential element read over a fixed [1024] stack array, nested reps times.
// `tab[k]+r` varies each outer pass so the reduction can't be shortcut; reps
// carries an os.args side effect so it stays runtime-unknown. Mirrors array_get.w.
import "core:fmt"
import "core:time"
import "core:os"

main :: proc() {
	reps := i64(976562) + i64(len(os.args)) - 1
	tab: [1024]i64
	for j: i64 = 0; j < 1024; j += 1 { tab[j] = j * 2654435761 + reps }
	t0 := time.tick_now()
	chk := reps
	for r: i64 = 0; r < reps; r += 1 {
		for k := 0; k < 1024; k += 1 { chk ~= tab[k] + r }
	}
	el := time.duration_seconds(time.tick_since(t0))
	ops := reps * 1024
	fmt.printf("%d\nops: %d\nelapsed: %.6fs\n", chk, ops, el)
}
