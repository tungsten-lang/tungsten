package main

import (
	"fmt"
	"sort"
	"time"
)

func main() {
	t0 := time.Now()

	const n = 2000000
	arr := make([]int, n)
	seed := uint32(42)
	for i := 0; i < n; i++ {
		seed = (seed*1103515245 + 12345) & 0x7FFFFFFF
		arr[i] = int(seed)
	}

	sort.Ints(arr)

	elapsed := time.Since(t0)
	fmt.Printf("first=%d last=%d\n", arr[0], arr[n-1])
	fmt.Printf("elapsed: %.3fs\n", elapsed.Seconds())
}
