package main

import (
	"fmt"
	"strings"
	"time"
)

func main() {
	t0 := time.Now()

	base := "the quick brown fox jumps over the lazy dog "
	text := strings.Repeat(base, 2500000)

	count := 0
	pos := 0
	for {
		idx := strings.Index(text[pos:], "fox")
		if idx == -1 {
			break
		}
		count++
		pos += idx + 3
	}

	elapsed := time.Since(t0)
	fmt.Println(count)
	fmt.Printf("elapsed: %.3fs\n", elapsed.Seconds())
}
