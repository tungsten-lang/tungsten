package main

// Wraparound (masked-index) array read: `tab[i & 1023]` in a flat loop, with a
// runtime-unknown trip count (a constant lets LLVM restructure by period).
// Mirrors array_mod.w.
import "core:fmt"
import "core:time"
import "core:os"

main :: proc() {
	n := i64(1000000000) + i64(len(os.args)) - 1
	chk: i64 = 0
	tab: [1024]i64
	for j: i64 = 0; j < 1024; j += 1 { tab[j] = j * 2654435761 }
	t0 := time.tick_now()
	for i: i64 = 0; i < n; i += 1 { chk ~= tab[i & 1023] }
	el := time.duration_seconds(time.tick_since(t0))
	fmt.printf("%d\nops: %d\nelapsed: %.6fs\n", chk, n, el)
}
