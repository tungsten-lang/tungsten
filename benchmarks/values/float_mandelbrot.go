package main

import (
	"fmt"
	"time"
)

func main() {
	t0 := time.Now()

	total := int64(0)
	for py := 0; py < 2000; py++ {
		ci := -1.5 + float64(py)*3.0/2000.0
		for px := 0; px < 2000; px++ {
			cr := -2.0 + float64(px)*3.0/2000.0
			zr := 0.0
			zi := 0.0
			iter := int64(0)
			for iter < 50 {
				if zr*zr+zi*zi > 4.0 {
					break
				}
				newZr := zr*zr - zi*zi + cr
				zi = 2.0*zr*zi + ci
				zr = newZr
				iter++
			}
			total += iter
		}
	}

	elapsed := time.Since(t0)
	fmt.Println(total)
	fmt.Printf("elapsed: %.3fs\n", elapsed.Seconds())
}
