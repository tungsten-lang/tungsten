# microGPT C reference benchmarks

Vendored from [talos-vs-macbook](https://github.com/exolabs/talos-vs-macbook)
(MIT, © 2026 Alex Cheema). These are the CPU baselines we measure
Tungsten's GPU port-back against.

| binary              | what it does                                    |
| ------------------- | ----------------------------------------------- |
| `bench_c`           | Single-stream NEON fp32, batch=1                |
| `bench_c_batch_mt`  | Batched NEON fp32, multi-threaded (pthreads)    |
| `bench_c_sme`       | Single-thread Apple Accelerate (cblas_sgemm)    |
| `bench_c_sme_mt`    | Threaded Accelerate (one BLAS context per core) |

## build

From repo root:

```bash
cd bits/tungsten-llama/lib/microgpt/c
clang -O3 -march=native -ffast-math bench_c.c           -o bench_c
clang -O3 -march=native -ffast-math bench_c_batch_mt.c  -o bench_c_batch_mt -lpthread
clang -O3 -march=native -ffast-math bench_c_sme.c       -o bench_c_sme      -framework Accelerate
clang -O3 -march=native -ffast-math bench_c_sme_mt.c    -o bench_c_sme_mt   -framework Accelerate -lpthread
```

## run

The weights file is shared with the Tungsten ports:
`bits/tungsten-llama/lib/models/microgpt/weights_fp32.bin` (16768 bytes).

Each binary takes a slightly different CLI; see the comment block at the
top of each `.c` file. Typical runs:

```bash
./bench_c
./bench_c_batch_mt 3072 12 1000 100      # B=3072 streams, T=12 threads
./bench_c_sme 256 1000                    # B=256 streams
./bench_c_sme_mt 3072 12 1000 100         # B=3072 streams, T=12 threads
```
