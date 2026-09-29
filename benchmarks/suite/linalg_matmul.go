package main

import (
	"fmt"
	"time"
)

func main() {
	n := 512
	kIters := 8
	nn := n * n
	a := make([]float32, nn)
	b := make([]float32, nn)
	c := make([]float32, nn)
	for i := 0; i < nn; i++ {
		a[i] = float32((i*31+7)%17) / 17.0
		b[i] = float32((i*13+3)%19) / 19.0
	}
	matmul(a, b, c, n)
	t0 := time.Now()
	for k := 0; k < kIters; k++ {
		matmul(a, b, c, n)
	}
	elapsed := time.Since(t0).Seconds()
	fmt.Printf("%d\n", int(c[0]*1_000_000))
	fmt.Printf("elapsed: %vs\n", elapsed)
}

func matmul(a, b, c []float32, n int) {
	for i := 0; i < n; i++ {
		for j := 0; j < n; j++ {
			var acc float32
			for k := 0; k < n; k++ {
				acc += a[i*n+k] * b[k*n+j]
			}
			c[i*n+j] = acc
		}
	}
}
