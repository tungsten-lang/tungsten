// Go matmul benchmark using gonum/mat. Build:
//   go mod init matmul && go get gonum.org/v1/gonum/mat && go run matmul.go 256 100

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strconv"
	"time"

	"gonum.org/v1/gonum/mat"
)

func main() {
	N, K := 256, 100
	if len(os.Args) > 1 {
		N, _ = strconv.Atoi(os.Args[1])
	}
	if len(os.Args) > 2 {
		K, _ = strconv.Atoi(os.Args[2])
	}

	aData := make([]float64, N*N)
	bData := make([]float64, N*N)
	for i := 0; i < N*N; i++ {
		aData[i] = float64((i*31+7)%17) / 17.0
		bData[i] = float64((i*13+3)%19) / 19.0
	}
	A := mat.NewDense(N, N, aData)
	B := mat.NewDense(N, N, bData)
	var C mat.Dense

	// Warm up.
	C.Mul(A, B)

	times := make([]float64, K)
	for i := 0; i < K; i++ {
		t0 := time.Now()
		C.Mul(A, B)
		times[i] = float64(time.Since(t0).Microseconds()) / 1000.0
	}
	sort.Float64s(times)
	medianMs := times[K/2]
	gflops := (2.0 * float64(N) * float64(N) * float64(N)) / (medianMs * 1e6)

	// Anti-DCE.
	_ = C.At(0, 0)

	enc := json.NewEncoder(os.Stdout)
	enc.Encode(map[string]any{
		"impl":      "go-gonum",
		"N":         N,
		"K":         K,
		"median_ms": medianMs,
		"gflops":    gflops,
		"note":      "gonum uses float64 internally; results aren't directly comparable to f32 implementations",
	})
	_ = fmt.Sprintf("") // satisfy import
}
