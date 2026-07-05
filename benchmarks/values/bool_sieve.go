package main

import (
	"fmt"
	"time"
)

func main() {
	t0 := time.Now()

	n := 1000000
	isPrime := make([]bool, n+1)
	for i := range isPrime {
		isPrime[i] = true
	}
	isPrime[0] = false
	isPrime[1] = false

	i := 2
	for i*i <= n {
		if isPrime[i] {
			j := i * i
			for j <= n {
				isPrime[j] = false
				j += i
			}
		}
		i++
	}

	count := 0
	for k := 0; k <= n; k++ {
		if isPrime[k] {
			count++
		}
	}

	elapsed := time.Since(t0)
	fmt.Println(count)
	fmt.Printf("elapsed: %.3fs\n", elapsed.Seconds())
}
