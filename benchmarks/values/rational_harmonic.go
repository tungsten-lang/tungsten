package main

import (
	"fmt"
	"math/big"
	"time"
)

func main() {
	t0 := time.Now()

	num := big.NewInt(0)
	den := big.NewInt(1)
	g := new(big.Int)
	bi := new(big.Int)

	for i := int64(1); i <= 3000; i++ {
		bi.SetInt64(i)
		// num/den + 1/i = (num*i + den) / (den*i)
		num.Mul(num, bi)
		num.Add(num, den)
		den.Mul(den, bi)
		// GCD reduce
		g.GCD(nil, nil, num, den)
		num.Div(num, g)
		den.Div(den, g)
	}

	digits := len(num.String())

	elapsed := time.Since(t0)
	fmt.Println(digits)
	fmt.Printf("elapsed: %.3fs\n", elapsed.Seconds())
}
