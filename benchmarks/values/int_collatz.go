package main

import (
	"fmt"
	"time"
)

func main() {
	t0 := time.Now()

	sum := int64(0)
	for n := int64(1); n <= 1000000; n++ {
		x := n
		steps := int64(0)
		for x != 1 {
			if x%2 == 0 {
				x = x / 2
			} else {
				x = 3*x + 1
			}
			steps++
		}
		sum += steps
	}

	elapsed := time.Since(t0)
	fmt.Println(sum)
	fmt.Printf("elapsed: %.3fs\n", elapsed.Seconds())
}
