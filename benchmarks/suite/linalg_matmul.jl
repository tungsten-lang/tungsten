using LinearAlgebra
n = 512
k_iters = 8
# Fill in C/NumPy row-major order. Julia's reshape is column-major, so a
# 1-D reshape would disagree with the CBLAS/NumPy peers on C[1,1].
A = zeros(Float32, n, n)
B = zeros(Float32, n, n)
for i in 0:(n * n - 1)
    r = div(i, n) + 1
    c = (i % n) + 1
    A[r, c] = Float32((i * 31 + 7) % 17) / 17f0
    B[r, c] = Float32((i * 13 + 3) % 19) / 19f0
end
C = A * B
t0 = time_ns()
for _ in 1:k_iters
    C = A * B
end
t1 = time_ns()
println(Int(round(C[1, 1] * 1_000_000)))
println("elapsed: $((t1 - t0) / 1e9)s")
