package main

import (
	"fmt"
	"time"
)

func main() {
	t0 := time.Now()

	const n = 10000000
	a := make([]int, n)
	for i := 0; i < n; i++ {
		a[i] = i % 10
	}

	b := make([]int, 0, n)
	for len(a) > 0 {
		b = append(b, a[0])
		a = a[1:]
	}

	elapsed := time.Since(t0)
	fmt.Printf("length=%d first=%d last=%d\n", len(b), b[0], b[len(b)-1])
	fmt.Printf("elapsed: %.3fs\n", elapsed.Seconds())
}
