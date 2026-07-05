package main

import (
	"fmt"
	"runtime"
	"sync"
	"time"
)

const N = 100_000_000

func colorCycleWorker(start, end int, acc *uint64) {
	var a uint64
	for i := start; i < end; i++ {
		r := uint32(i & 0xFF)
		g := uint32((i >> 8) & 0xFF)
		b := uint32((i >> 16) & 0xFF)
		c := (r << 24) | (g << 16) | (b << 8) | 0xFF
		a += uint64((c >> 24) & 0xFF)
	}
	*acc = a
}

func bench(ngoroutines int, baseMops float64) {
	per := N / ngoroutines
	accs := make([]uint64, ngoroutines)
	var wg sync.WaitGroup

	t0 := time.Now()
	for t := 0; t < ngoroutines; t++ {
		wg.Add(1)
		start := t * per
		end := start + per
		if t == ngoroutines-1 {
			end = N
		}
		go func(idx, s, e int) {
			defer wg.Done()
			colorCycleWorker(s, e, &accs[idx])
		}(t, start, end)
	}
	wg.Wait()
	dt := time.Since(t0)

	mops := float64(N) / dt.Seconds() / 1e6
	scaling := mops / baseMops
	if baseMops == 0 {
		scaling = 1.0
	}
	fmt.Printf("  %2d goroutines: %8.1fM colors/sec  (%5.2f ns/color)  %.1fx\n",
		ngoroutines, mops, float64(dt.Nanoseconds())/float64(N), scaling)
}

func main() {
	runtime.GOMAXPROCS(runtime.NumCPU())
	fmt.Printf("\n  Color cycle — %dM colors, goroutines (uint32 pack)\n\n", N/1_000_000)

	// Single goroutine baseline
	var acc uint64
	t0 := time.Now()
	colorCycleWorker(0, N, &acc)
	dt := time.Since(t0)
	baseMops := float64(N) / dt.Seconds() / 1e6
	fmt.Printf("  %2d goroutine:  %8.1fM colors/sec  (%5.2f ns/color)  1.0x\n",
		1, baseMops, float64(dt.Nanoseconds())/float64(N))

	counts := []int{2, 4, 8, 16, 32, 64}
	for _, n := range counts {
		bench(n, baseMops)
	}
	fmt.Println()
}
