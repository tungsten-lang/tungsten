package main

import (
	"fmt"
	"time"
)

func main() {
	t0 := time.Now()

	cRe := -0.7
	cIm := 0.27015
	total := int64(0)
	for py := 0; py < 2000; py++ {
		ziInit := -1.5 + float64(py)*3.0/2000.0
		for px := 0; px < 2000; px++ {
			zr := -1.5 + float64(px)*3.0/2000.0
			zi := ziInit
			iter := int64(0)
			for iter < 50 {
				if zr*zr+zi*zi > 4.0 {
					break
				}
				newZr := zr*zr - zi*zi + cRe
				zi = 2.0*zr*zi + cIm
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
