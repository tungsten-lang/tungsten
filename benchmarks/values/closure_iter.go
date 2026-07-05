package main

import (
	"fmt"
	"time"
)

func main() {
	t0 := time.Now()

	const n = 2000000

	// map: x -> x*3+1, filter: x%2==0, map: x -> x/2, reduce: sum
	sum := int64(0)
	for x := int64(0); x < n; x++ {
		v := x*3 + 1
		if v%2 == 0 {
			sum += v / 2
		}
	}

	elapsed := time.Since(t0)
	fmt.Println(sum)
	fmt.Printf("elapsed: %.3fs\n", elapsed.Seconds())
}
