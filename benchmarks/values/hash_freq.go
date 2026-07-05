package main

import (
	"fmt"
	"strconv"
	"time"
)

func main() {
	t0 := time.Now()

	const numWords = 1000
	const numIter = 5000000

	words := make([]string, numWords)
	for i := 0; i < numWords; i++ {
		words[i] = "word" + strconv.Itoa(i)
	}

	freq := make(map[string]int, numWords)
	seed := uint32(42)
	for i := 0; i < numIter; i++ {
		seed = (seed*1103515245 + 12345) & 0x7FFFFFFF
		word := words[seed%numWords]
		freq[word]++
	}

	maxFreq := 0
	for _, v := range freq {
		if v > maxFreq {
			maxFreq = v
		}
	}

	elapsed := time.Since(t0)
	fmt.Println(maxFreq)
	fmt.Printf("elapsed: %.3fs\n", elapsed.Seconds())
}
