// Swift matmul benchmark. Two implementations bundled:
//   - vDSP_mmul via Accelerate (CPU, AMX co-processor)
//   - MLX matmul (Metal GPU)
//
// Build:
//   swift build -c release && .build/release/matmul accelerate 256 100
//   .build/release/matmul mlx 256 100
//
// Requires Package.swift in the same directory with MLX dependency.

import Foundation
import Accelerate

#if canImport(MLX)
import MLX
#endif

func nowMs() -> Double {
    return Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000.0
}

func runAccelerate(N: Int, K: Int) {
    var aData = [Float](repeating: 0, count: N * N)
    var bData = [Float](repeating: 0, count: N * N)
    var cData = [Float](repeating: 0, count: N * N)
    for i in 0..<(N * N) {
        aData[i] = Float((i * 31 + 7) % 17) / 17.0
        bData[i] = Float((i * 13 + 3) % 19) / 19.0
    }

    // Warm up.
    vDSP_mmul(aData, 1, bData, 1, &cData, 1, vDSP_Length(N), vDSP_Length(N), vDSP_Length(N))

    var times = [Double]()
    for _ in 0..<K {
        let t0 = nowMs()
        vDSP_mmul(aData, 1, bData, 1, &cData, 1, vDSP_Length(N), vDSP_Length(N), vDSP_Length(N))
        times.append(nowMs() - t0)
    }
    times.sort()
    let medianMs = times[K / 2]
    let gflops = (2.0 * Double(N) * Double(N) * Double(N)) / (medianMs * 1e6)

    print("{\"impl\":\"swift-accelerate\",\"N\":\(N),\"K\":\(K),\"median_ms\":\(medianMs),\"gflops\":\(gflops)}")
}

#if canImport(MLX)
func runMLX(N: Int, K: Int) {
    let aFlat = (0..<(N * N)).map { Float(($0 * 31 + 7) % 17) / 17.0 }
    let bFlat = (0..<(N * N)).map { Float(($0 * 13 + 3) % 19) / 19.0 }
    let a = MLXArray(aFlat).reshaped([N, N])
    let b = MLXArray(bFlat).reshaped([N, N])

    // Warm up + force materialization.
    var c = matmul(a, b)
    c.eval()

    var times = [Double]()
    for _ in 0..<K {
        let t0 = nowMs()
        c = matmul(a, b)
        c.eval()
        times.append(nowMs() - t0)
    }
    times.sort()
    let medianMs = times[K / 2]
    let gflops = (2.0 * Double(N) * Double(N) * Double(N)) / (medianMs * 1e6)

    print("{\"impl\":\"swift-mlx\",\"N\":\(N),\"K\":\(K),\"median_ms\":\(medianMs),\"gflops\":\(gflops)}")
}
#endif

let args = CommandLine.arguments
let backend = args.count > 1 ? args[1] : "accelerate"
let N = args.count > 2 ? Int(args[2]) ?? 256 : 256
let K = args.count > 3 ? Int(args[3]) ?? 100 : 100

switch backend {
case "accelerate":
    runAccelerate(N: N, K: K)
case "mlx":
    #if canImport(MLX)
    runMLX(N: N, K: K)
    #else
    FileHandle.standardError.write("MLX not available — install via SPM, see Package.swift\n".data(using: .utf8)!)
    exit(1)
    #endif
default:
    FileHandle.standardError.write("usage: matmul {accelerate|mlx} [N] [K]\n".data(using: .utf8)!)
    exit(2)
}
