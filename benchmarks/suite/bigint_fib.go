package main

import (
	"fmt"
	"math/big"
	"time"
)

func main() {
	t0 := time.Now()

	a := big.NewInt(0)
	b := big.NewInt(1)
	tmp := new(big.Int)

	for i := 0; i < 100000; i++ {
		tmp.Set(b)
		b.Add(a, b)
		a.Set(tmp)
	}

	digits := len(b.String())

	elapsed := time.Since(t0)
	fmt.Println(digits)
	fmt.Printf("elapsed: %.3fs\n", elapsed.Seconds())
}
