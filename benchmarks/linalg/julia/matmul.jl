#!/usr/bin/env julia
# Julia matmul benchmark. Uses Julia's built-in `*` for matrices,
# which delegates to OpenBLAS by default. Run:
#   julia matmul.jl 256 100

using LinearAlgebra
using Statistics
using JSON

function main()
    N = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 256
    K = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 100

    idx = collect(Float32, 0:(N*N-1))
    A = reshape(Float32.((idx .* 31 .+ 7) .% 17 ./ 17), N, N)
    B = reshape(Float32.((idx .* 13 .+ 3) .% 19 ./ 19), N, N)

    # Warm up.
    C = A * B

    times = Float64[]
    for _ in 1:K
        t0 = time_ns()
        C = A * B
        push!(times, (time_ns() - t0) / 1e6)
    end
    sort!(times)
    median_ms = times[K ÷ 2 + 1]
    gflops = (2.0 * N * N * N) / (median_ms * 1e6)

    # Anti-DCE.
    _ = C[1, 1]

    println(JSON.json(Dict(
        "impl" => "julia",
        "N" => N,
        "K" => K,
        "median_ms" => round(median_ms; digits=4),
        "gflops" => round(gflops; digits=2),
        "blas" => string(BLAS.vendor()),
    )))
end

main()
