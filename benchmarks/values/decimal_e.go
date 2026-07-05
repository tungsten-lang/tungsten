package main

import (
	"fmt"
	"time"
)

func main() {
	t0 := time.Now()

	var e float64
	for rep := 0; rep < 100000; rep++ {
		e = 0.0
		factorial := 1.0
		for i := 0; i <= 100; i++ {
			e = e + 1.0/factorial
			factorial = factorial * float64(i+1)
		}
	}

	result := int64(e * 1000000.0)

	elapsed := time.Since(t0)
	fmt.Println(result)
	fmt.Printf("elapsed: %.3fs\n", elapsed.Seconds())
}
