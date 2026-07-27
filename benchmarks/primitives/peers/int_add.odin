package main

import "core:fmt"
import "core:time"
import "core:os"

main :: proc() {
	n := i64(300000000) + i64(len(os.args)) - 1
	s: i64 = 1
	t0 := time.tick_now()
	for i: i64 = 0; i < n; i += 1 { s = s + (s ~ i) }
	el := time.duration_seconds(time.tick_since(t0))
	fmt.printf("%d\nops: %d\nelapsed: %.6fs\n", s, n, el)
}
