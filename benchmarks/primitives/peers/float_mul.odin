package main

import "core:fmt"
import "core:time"
import "core:os"

main :: proc() {
	n := i64(20000000) + i64(len(os.args)) - 1
	f: f64 = 0.5
	t0 := time.tick_now()
	for i: i64 = 0; i < n; i += 1 { f = 3.9 * f * (1.0 - f) }
	el := time.duration_seconds(time.tick_since(t0))
	fmt.printf("%.10f\nops: %d\nelapsed: %.6fs\n", f, n, el)
}
