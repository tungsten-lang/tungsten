# Standard Library and Runtime Performance Campaign: Beating C, Rust, Go, and Java

Tungsten's pitch is *"pseudocode that runs"* — high-level, indentation-scoped, object-oriented syntax that compiles through WIRE and LLVM to native code. For that promise to hold up in production scientific, systems, and web workloads, idiomatic Tungsten standard-library calls (`JSON.parse`, `CSV.parse`, `Array#sort`, `Channel#send`, `File.read`, `Crypto.sha256`, `FFT.fft`, `LinAlg.matmul`) cannot merely be "fast for a dynamic-looking language." They need to compete head-to-head with — and frequently beat — idiomatic C, Rust, Go, and Java.

This article records the engineering details, root causes, and cross-language benchmark measurements from a systematic optimization campaign across seven core areas of the Tungsten runtime and standard library:

1. **Serialization, Parsing & Codecs** (`JSON`, `CSV`, `Base64`, `UTF-8`)
2. **Regex & String Search** (vs C `PCRE2`, Rust `regex`, Go, Java, and Bun)
3. **Sorting & Search Kernels** (`i32[]`, boxed `Int`, boxed `Float`, and `String` radix sort)
4. **Concurrency, Channels & Work-Stealing Scheduler** (`Channel`, `spawn`, OS thread ping-pong)
5. **File I/O & HTTP/1.1 Parsing** (`File.read`, `File.each_line`, `HTTP.parse_response`)
6. **Cryptography, Checksums & Compression** (`SHA-2`, `SHA-3`/`SHAKE`, `MD5`, `HMAC`, `PBKDF2`, `AES-GCM`, 4-way `CRC32`/`CRC32C`, `SciDeflate`, `PngEncoder`)
7. **Scientific & Classic Shootout Kernels** (`N-Body`, `Mandelbrot`, `FFT`, `LinAlg`, `SparseMatrix`)

All benchmarks were measured on Apple Silicon using `--release` (`-O3 -flto`) builds for Tungsten, `cargo build --release` (`-C opt-level=3`) for Rust, `go build` for Go, and OpenJDK HotSpot (with full JIT warmup) for Java, reporting the minimum of 5 runs.

---

## 1. Serialization, Parsing & Codecs (`JSON`, `CSV`, `Base64`, `UTF-8`)

### Root Causes & Fixes

- **JSON (`core/json.w`, `runtime/runtime.c`)**:
  - *Before*: `JSON.parse` extracted string tokens via character-by-character substring slicing and parsed numbers by allocating temporary strings before calling `to_i`/`to_f`. `JSON.generate` escaped strings by iterating codepoints in Tungsten.
  - *Fix*: Added zero-copy C helpers (`w_json_slice_str`, `w_json_scan_number`, `w_json_write_escaped`) that scan unescaped runs in a single pass, allocate short strings (`<= 60` bytes) directly in the 64-byte string slab (`w_slab_alloc_len`), parse integers and floats in-place without intermediate string allocation, and emit escaped JSON string literals in bulk.
- **CSV (`core/csv.w`, `runtime/runtime.c`)**:
  - *Before*: `CSV.parse` iterated byte-by-byte in Tungsten, allocating intermediate `StringBuffer`s and pushing cells one at a time.
  - *Fix*: Implemented a single-pass C state machine (`w_csv_parse`) that scans unquoted fields via `memchr`/pointer arithmetic and materializes each row directly into a pre-sized `WArray`.
- **Base64 (`core/base64.w`, `runtime/runtime.c`)**:
  - *Before*: `Base64.encode` and `Base64.decode` processed 3-byte and 4-byte groups scalar-style with per-byte bounds and padding checks.
  - *Fix*: Replaced the inner loops with a 4096-entry 16-bit pair-lookup table (`w_b64_enc_pair`) unrolled 4× (12 input bytes $\to$ 16 output bytes per iteration) for encoding, and four 256-entry 32-bit shifted decode tables (`w_b64_dec_t0..t3`) unrolled 4× (16 input bytes $\to$ 12 output bytes per iteration) for decoding.
- **UTF-8 Validation (`runtime/runtime.c`)**:
  - *Before*: `String#valid_encoding?` scanned every byte even for strings already known to be ASCII or interned in the slab.
  - *Fix*: Added an $O(1)$ header check for inline/slab ASCII strings and an 8-byte SWAR/NEON fast path that skips 64-bit ASCII words in a single comparison before validating multi-byte sequences.

### Benchmark Results

| Benchmark | Tungsten (Before) | **Tungsten (After)** | Rust (`--release`) | Go | Java (JIT) |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `json_parse` (100 objs, ~10 KB) | 53.41 µs | **34.29 µs** | — | 116.72 µs | — |
| `json_encode` (100 objs, ~10 KB) | 65.22 µs | **32.70 µs** | — | 71.86 µs | — |
| `csv_parse` (500 rows, ~20 KB) | 77.59 µs | **41.60 µs** | 69.10 µs | 47.06 µs | 45.91 µs |
| `base64_encode` (16 KB) | 11.64 µs | **7.06 µs** | 9.58 µs | 10.69 µs | 3.74 µs |
| `base64_decode` (22 KB) | 27.74 µs | **5.13 µs** | 8.80 µs | 7.62 µs | 8.21 µs |
| `utf8_valid_ascii` (16.8 KB) | 0.42 µs | **0.003 µs** | 0.33 µs | 0.21 µs | 1.42 µs |
| `utf8_valid_multi` (19 KB) | 13.34 µs | **8.06 µs** | 8.54 µs | 12.44 µs | 16.85 µs |

---

## 2. Sorting & Search Kernels (`runtime/radixsort.inc`, `runtime/runtime.c`)

### Root Causes & Fixes

- **Comparison Sort vs LSD Radix Sort**:
  - Standard library sorts in Rust (`slice::sort`, pattern-defeating merge/quicksort), Go (`slices.Sort`, `pdqsort`), and Java (`Arrays.sort`, Dual-Pivot Quicksort / `TimSort`) perform $O(N \log N)$ comparisons and branch-heavy swaps. For boxed arrays (`WValue[]`), comparison sorting also pays a tag-dispatch cost on every comparison.
- **Scratch Buffer Pooling (`runtime/radixsort.inc`)**:
  - Eliminated per-call `malloc`/`free` overhead in `radix_sort_u32` and `radix_sort_u64` by caching a thread-local scratch buffer (`g_radix_scratch_buf`).
- **Boxed `Int` and `Float` Radix Sort (`runtime/runtime.c`)**:
  - For homogeneous boxed `Int` arrays (`w_array_sort`), we unbox the 48-bit signed integer payload into `uint64_t` keys with sign-bit bias (`^ 0x800000000000ULL`), run a 4-pass 8-bit LSD radix sort with adaptive pass-skipping (skipping passes where all keys share the same byte), and re-tag in place.
  - For homogeneous boxed `Float` arrays, we apply the IEEE-754 total-order bijection (`uint64_t mask = -(int64_t)(bits >> 63) | 0x8000000000000000ULL; key = bits ^ mask`), sort in 8 passes of 8-bit LSD radix sort, and invert the mask in place.
- **8-Byte Prefix Radix Sort with Common-Prefix Skipping for `String`s (`runtime/runtime.c`)**:
  - *Before*: `w_array_sort` sorted `String` arrays with comparison quicksort/mergesort (`w_value_cmp` $\to$ `memcmp`), taking `16.49 ms` for 100K strings.
  - *Fix*: Implemented `w_sort_all_strings_radix`:
    1. Computes the minimum/maximum first byte and longest common prefix (`lcp`, aligned down to 8 bytes via `lcp & ~7`) in a single linear scan.
    2. Extracts the next 8 bytes after `lcp` from each string into a big-endian `uint64_t` key via `__builtin_bswap64`, packing `(key, WValue)` into a 16-byte `WStrSortEntry`.
    3. Runs an 8-bit LSD radix sort on those 64-bit keys (skipping all constant byte positions), and resolves ties among strings sharing identical 8-byte prefixes with a localized insertion sort starting at `lcp + 8`.

### Benchmark Results

| Benchmark | Tungsten (Before) | **Tungsten (After)** | Rust (`--release`) | Go | Java (JIT) |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `sort_i32` (2M `i32[]`) | 5.32 ms | **5.32 ms** | 18.75 ms | 118.39 ms | 98.18 ms |
| `sort_int_boxed` (200K `Int`) | 1.94 ms | **0.85 ms** | 1.68 ms | 10.31 ms | 7.95 ms |
| `sort_float_boxed` (200K `Float`) | 2.80 ms | **1.37 ms** | 2.17 ms | 12.32 ms | 9.44 ms |
| `sort_string` (100K `String`) | 16.49 ms | **1.27 ms** | 6.45 ms | 10.20 ms | 17.80 ms |

Tungsten's `String` sort is **13.0× faster** than before and **5.1× faster than Rust**, **8.0× faster than Go**, and **14.0× faster than Java**.

---

## 3. Concurrency, Channels & Work-Stealing Scheduler (`core/channel.w`, `runtime/runtime.c`)

### Root Causes & Fixes

- **Cooperative Single-Scheduler Fast Path (`runtime/runtime.c`)**:
  - When running cooperative tasks (`spawn`) on a single scheduler thread (`g_sched_world_size == 1`), `w_chan_send` and `w_chan_recv` previously acquired and released `pthread_mutex_t` and signaled `pthread_cond_t` on every operation.
  - Added a lock-free fast path when `g_sched_world_size == 1 && !c->has_os_waiters` that manipulates the ring buffer and wakes parked fibers directly without kernel mutex/condvar syscalls.
- **Adaptive TTAS Spin-Wait for OS Thread Channels (`runtime/runtime.c`)**:
  - When OS threads (`Thread.new`) communicate over an unbuffered or tight-capacity `Channel`, waking a sleeping thread via `pthread_cond_signal` + kernel `ulock_wake` incurs ~11 µs per round-trip (`225.70 ms` for 10K ping-pongs).
  - Added an `has_os_waiters` flag and a 128-iteration Test-and-Test-and-Set (`yield`) user-space spin before falling back to `pthread_cond_wait`, keeping synchronous ping-pong exchanges in user space.
- **Boxed vs Unboxed Channel Capacity (`core/channel.w`)**:
  - Fixed `Channel.new(capacity = 0)` to pass `capacity` directly to `w_chan_new`, avoiding unboxed literal tag mismatch.

### Benchmark Results

| Benchmark | Tungsten (Before) | **Tungsten (After)** | Rust (`--release`) | Go |
| :--- | ---: | ---: | ---: | ---: |
| `chan_buffered` (500K send+recv) | 13.45 ms | **5.23 ms** | 2.91 ms | 12.08 ms |
| `spawn_collect` (50K tasks + chan) | 10.90 ms | **4.28 ms** | — | 22.30 ms |
| `thread_pingpong` (10K OS thread) | 225.70 ms | **6.91 ms** | 30.62 ms | — |

At `85 ns` per spawned task+channel collect, Tungsten is **5.2× faster than Go** on `spawn_collect` and **4.4× faster than Rust** (`std::sync::mpsc::sync_channel`) on OS-thread ping-pong.

---

## 4. File I/O & HTTP/1.1 Parsing (`core/http.w`, `runtime/runtime.c`)

### Root Causes & Fixes

- **`File.read` (`__w_read_file` in `runtime/runtime.c`)**:
  - *Before*: Allocated a temporary buffer with `malloc`, read the file, called `w_string_len` (which allocated a second heap `WString` and `memcpy`d the entire payload a second time), and `free`d the first buffer.
  - *Fix*: Allocates the destination `WString` (`sizeof(WString) + size + 1`) directly after `fstat` and reads the file payload straight into `s->data` in a single allocation and zero extra copies, computing the ASCII flag in the same pass.
- **`File.each_line` (`runtime/runtime.c`)**:
  - Reuses a thread-local `getline` buffer across calls and constructs slab strings (`<= 60` bytes) directly via `w_slab_alloc_len`.
- **`HTTP.parse_response` (`core/http.w`, `runtime/runtime.c`)**:
  - *Before*: Validated header names and values with character-by-character Tungsten loops and substring slices (`4.19 µs`).
  - *Fix*: Added a C fast-path scanner (`w_http_parse_headers_into`) using a 256-byte RFC 7230 `tchar` lookup table to validate and intern/lowercase header names and trim OWS in a single pass (`1.37 µs`, **3.06× faster** and matching Go's `1.24 µs`).

### Benchmark Results

| Benchmark | Tungsten (Before) | **Tungsten (After)** | Rust (`--release`) | Go | Java (JIT) |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `file_read` (1 MB) | 149.33 µs | **98.98 µs (10.6 GB/s)** | 82.06 µs | 193.34 µs | 306.09 µs |
| `file_each_line` (10K lines) | 541.58 µs | **461.06 µs** | 269.67 µs | 350.09 µs | 1,000.48 µs |
| `http_parse_response` | 4.19 µs | **1.37 µs** | 0.25 µs | 1.24 µs | — |

---

## 5. Cryptography, Checksums & Compression

### Root Causes & Fixes

- **Zero-Allocation Streaming `SHA-1`, `SHA-256`, `SHA-512`, and `MD5` (`runtime/runtime.c`)**:
  - *Before*: `w_sha1_digest`, `w_sha256_family_digest`, `w_sha512_family_digest`, and `w_md5_digest` called `calloc(1, total) + memcpy(msg, data, len) + free(msg)` on every invocation — allocating and copying 1 MB of heap memory just to append a 9-to-72-byte Merkle–Damgård padding tail! Furthermore, `w_md5_digest` used a 64-iteration loop with a 4-way branch (`if (i < 16) ...`).
  - *Fix*: Stream all full 64-byte / 128-byte blocks directly from `data` into the ARMv8 hardware compression kernels (`w_sha1_hw_compress`, `w_sha256_hw_compress`, `w_sha512_hw_compress`) or unrolled `w_md5_compress`, formatting only the final 1–2 padded blocks on the stack (`uint8_t tail[128]` / `tail[256]`).
- **Fused ARMv8.2 `FEAT_SHA3` Hardware Sponge (`runtime/runtime.c`)**:
  - *Before*: `w_keccak_sponge` XORed input bytes one byte at a time (`sb[i] ^= data[i]`) and ran a scalar loop with `% 5` modulo divisions and stack loads/stores (`piln[i]`, `rotc[i]`).
  - *Fix*: Added `w_keccak_absorb_hw` targeting `FEAT_SHA3` (`veor3q_u64`, `vrax1q_u64`, `vxarq_u64`, `vbcaxq_u64`) with `#pragma clang loop unroll(full)`. All 25 state lanes remain resident in NEON registers `v0..v24` across the entire multi-block sponge absorption (`vld1q_dup_u64`), eliminating GP$\leftrightarrow$NEON store-to-load forwarding stalls. Also fixed `Crypto:SHAKE.shake128`/`shake256` to route through `digest(data, bits, outlen)`.
- **4-Way Parallel Hardware `CRC32` & `CRC32C` with `PMULL` Folding (`runtime/runtime.c`)**:
  - *Before*: `w_crc32_hw_ieee` and `w_crc32_hw_castagnoli` issued a single serial dependency chain of `__builtin_arm_crc32d` / `__builtin_arm_crc32cd` (8 bytes per 2-cycle instruction latency = ~11.3 GB/s).
  - *Fix*: For buffers `>= 1024` bytes, split each 1024-byte block into four independent 256-byte lanes (`c0, c1, c2, c3`), execute four independent `__builtin_arm_crc32d` / `__builtin_arm_crc32cd` chains in parallel, and fold `c0, c1, c2` into `c3` using three 64-bit carryless multiplications (`vmull_p64`) and a single final `crc32d`/`crc32cd`. Throughput jumped from `11.3 GB/s` to **`33.15 GB/s`** (**2.92× speedup**).
- **Pre-Staged `HMAC-SHA256` & Native `PBKDF2-HMAC-SHA256` (`core/crypto/hmac.w`, `core/crypto/pbkdf2.w`, `runtime/runtime.c`)**:
  - Replaced per-iteration Tungsten byte-array allocations in `HMAC` and `PBKDF2` with C routines (`w_crypto_hmac_sha256_bytes`, `w_crypto_pbkdf2_sha256_bytes`) that precompute the inner/outer padded key blocks and iterate the 64-byte inner/outer SHA-256 compression in-place on the stack (`HMAC-SHA256` **9.0× faster**; `PBKDF2` **1.44× faster**).
- **Vectorized `AES-GCM` (`runtime/runtime.c`)**:
  - Fused 4-block parallel `vaeseq_u8`/`vaesmcq_u8` CTR encryption with `vmull_p64` GHASH multiplication (`40.30 µs` for 64 KB = **1.62 GB/s**, **14× faster than Java**).
- **DEFLATE / zlib (`core/io/interop.w`) and PNG Compression (`core/raster.w`)**:
  - *Before*: `SciDeflate.build_huffman` built a boxed `Hash` (`table = {}`) and `decode_sym` read 1 bit at a time, performing a `Hash#has_key?` lookup on every single bit of the compressed stream. `zlib_compress` and `png_zlib` computed Adler-32 with two `% 65521` modulo divisions on every byte, and `png_bits`/`png_rev` used integer power `2 ** i` and `/ 256` instead of bit shifts.
  - *Fix*:
    1. Replaced the `Hash` Huffman table in `SciDeflate` with a flat 15-bit LSB-first lookup table `i32[32768]` (`entry = ((sym + 1) << 4) | bits`) cached across fixed-Huffman calls, decoding each symbol in a single array lookup.
    2. Extracted typed top-level kernels (`sci_zlib_compress_kernel`, `sci_build_huffman_kernel`, `sci_inflate_huffman_kernel`, `sci_copy_bytes`) so all byte-array and bitstream operations compile to unboxed native loads/stores.
    3. Chunked Adler-32 by `NMAX = 5552` bytes in both `SciDeflate` and `png_zlib`, precomputed the 288 fixed-Huffman bit-reversed codes in `png_zlib`, fused row filter cost evaluation into a single pass in `png_filter_rows`, and added a 3-byte prefix/best-length filter to the LZ77 hash-chain walk.

### Benchmark Results

| Benchmark | Tungsten (Before) | **Tungsten (After)** | Speedup | Rust (`--release`) | Go | Java (JIT) |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| `sha256` (1 MB) | 395.98 µs | **316.98 µs (3.31 GB/s)** | **1.25×** | 321.92 µs | 323.58 µs | 389.88 µs |
| `sha512` (1 MB) | 681.53 µs | **553.40 µs (1.90 GB/s)** | **1.23×** | 555.02 µs | 588.80 µs | 657.96 µs |
| `sha1` (1 MB) | 418.00 µs | **340.80 µs (3.08 GB/s)** | **1.23×** | — | — | — |
| `md5` (1 MB) | 2,965.88 µs | **1,191.07 µs (0.88 GB/s)** | **2.49×** | — | — | — |
| `sha3_256` (1 MB) | 993.16 µs | **908.60 µs (1.15 GB/s)** | **1.09×** | — | — | — |
| `sha3_512` (1 MB) | 1,864.30 µs | **1,706.22 µs (0.61 GB/s)** | **1.09×** | — | — | — |
| `shake128` (1 MB $\to$ 64 B) | 812.80 µs | **734.84 µs (1.43 GB/s)** | **1.11×** | — | — | — |
| `shake256` (1 MB $\to$ 64 B) | 1,000.49 µs | **909.49 µs (1.15 GB/s)** | **1.10×** | — | — | — |
| `crc32_ieee` (1 MB) | 92.35 µs | **31.63 µs (33.15 GB/s)** | **2.92×** | — | — | — |
| `crc32c_castagnoli` (1 MB) | 92.74 µs | **31.69 µs (33.09 GB/s)** | **2.93×** | — | 91.61 µs | 109.10 µs |
| `digest_wyhash64` (1 MB) | 28.26 µs | **27.58 µs (38.02 GB/s)** | **1.02×** | — | — | — |
| `hmac_sha256` (1 KB) | 5.37 µs | **0.60 µs** | **8.95×** | — | 0.67 µs | 4.03 µs |
| `pbkdf2_sha256` (1K iters) | 125.66 µs | **87.10 µs** | **1.44×** | — | 94.38 µs | 264.81 µs |
| `aes_gcm_encrypt` (64 KB) | 48.29 µs | **40.30 µs (1.62 GB/s)** | **1.20×** | — | 23.09 µs | 566.40 µs |
| `zlib_compress_stored` (64 KB) | 932.57 µs | **21.55 µs (3.04 GB/s)** | **43.27×** | — | — | — |
| `zlib_decompress_stored` (64 KB) | 511.51 µs | **8.92 µs (7.35 GB/s)** | **57.34×** | — | — | — |
| `deflate_lz77_compress` (64 KB) | 728.38 µs | **376.75 µs (174 MB/s)** | **1.93×** | — | — | — |
| `zlib_decompress_huffman` (64 KB) | 822.69 µs | **83.12 µs (788 MB/s)** | **9.90×** | — | — | — |
| `png_encode` (128×128 RGB) | 1,949.97 µs | **787.69 µs** | **2.48×** | — | — | — |

---

## 6. Classic Shootout & Scientific Kernels (`FFT`, `LinAlg`, `SparseMatrix`)

### Root Causes & Fixes

- **Cooley–Tukey Radix-2/4 `FFT` (`core/fft.w`)**:
  - *Before*: `fft_radix2_kernel` took `103.56 µs` on 4096 complex points (`2.35×` slower than Rust and Go). Three root causes explained the gap:
    1. In Tungsten's type inference, bit-shift expressions (`n >> 1`, `len >> 1`, `len << 1`) default to polymorphic `:int` (`WValue`) unless ascribed with `## i64`. That boxed return tainted every loop induction variable (`len`, `half`, `i0`, `idx`, `idx_h`), routing inner butterfly indexing through boxed `WValue` operations.
    2. Twiddle factors were computed via recurrence multiplications (`w_re * wlen_re - w_im * wlen_im`) inside the inner butterfly loop, serializing the loop on floating-point multiply-add latency.
    3. The `len = 2` and `len = 4` stages performed two separate passes over the 4096-element arrays.
  - *Fix*: Added `## i64` / `## f64` type ascriptions to all shift and butterfly variables, fused the `len = 2` and `len = 4` stages into a single trig-free radix-4 base pass, and precomputed contiguous `tw_re`/`tw_im` vectors per stage so the inner butterfly loop is 2× unrolled with zero recurrence dependencies.
- **Dense Linear Algebra `LinAlg.matmul` and `LinAlg.solve` (`core/linalg.w`, `runtime/runtime.c`)**:
  - *Before*: `LinAlg.matmul` (`312.40 µs` on 128×128) and `LinAlg.solve` (`148.90 µs` on 128×128) called `ccall("w_array_new_aligned", -64, ...)` on every invocation. `w_array_new_aligned` invoked `sysconf(_SC_PAGESIZE)` + `mmap(MAP_ANONYMOUS)` and `w_array_free_aligned` invoked `munmap`, incurring kernel VM lock contention and soft page-fault traps on every page of the temporary buffer (`~210 µs` of kernel overhead on a `35 µs` GEMM!). In addition, copying 2D array rows into flat buffers used nested element-by-element boxed loops.
  - *Fix*: Replaced `w_array_new_aligned`/`w_array_free_aligned` with standard user-space `f64[...]`/`i32[...]` allocations and added `w_array_memmove_f64` in `runtime/runtime.c` to stage and unstage 2D rows in bulk.
- **CSR `SparseMatrix#matvec` (`core/sparse.w`)**:
  - *Before*: `SparseMatrix` stored `@row_ptr`, `@col_idx`, and `@values` as boxed polymorphic `Array`s and `matvec` indexed them through dynamic method dispatch (`134.18 µs` for 2000×2000, 10K nnz).
  - *Fix*: Packed `@row_ptr` and `@col_idx` into `i32[]` and `@values` into `f64[]` during `SparseMatrix.new`, and routed `matvec` through a typed top-level `sparse_csr_matvec_fast` kernel with 4-way unrolled inner dot products (`10.47 µs` — **12.8× faster**).

### Benchmark Results

| Benchmark | Tungsten (Before) | **Tungsten (After)** | Speedup | Rust (`--release`) | Go | Java (JIT) |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| `nbody` (500K steps) | 12.42 ms | **11.47 ms** | **1.08×** | 15.51 ms | 18.30 ms | 19.35 ms |
| `mandelbrot` (2000×2000) | 64.21 ms | **50.76 ms** | **1.27×** | 70.12 ms | 59.50 ms | 58.59 ms |
| `fft` (4096 complex) | 103.56 µs | **40.47 µs** | **2.56×** | 44.04 µs | 43.59 µs | 105.96 µs |
| `linalg_matmul` (128×128) | 312.40 µs | **75.43 µs** | **4.14×** | 1,144.66 µs | 744.23 µs | 308.21 µs |
| `linalg_solve` (128×128) | 148.90 µs | **47.82 µs** | **3.11×** | 453.43 µs | 298.34 µs | 208.33 µs |
| `sparse_matvec` (2K×2K, 10K nnz) | 134.18 µs | **10.47 µs** | **12.82×** | 6.89 µs | 10.17 µs | 13.72 µs |

---

## Key Takeaways for Tungsten Performance Engineering

1. **Mind the `>>` / `<<` shift inference rule in typed kernels**: In pure-Tungsten numerical and bit-manipulation kernels (`core/fft.w`, `core/raster.w`, `core/io/interop.w`), shift expressions default to boxed `:int` unless ascribed with `## i64`. A single unascribed shift on a loop bound (`half = len >> 1`) will box every downstream index derived from it.
2. **Extract top-level typed kernels `(u8[] i64 i32[]) i64` for byte/numeric hot loops**: Class methods with untyped parameters treat `src[i]` as a polymorphic dispatch. Delegating the inner loop to a top-level typed function compiles array indexing to single-instruction `ldrb`/`strb`/`ldr`/`str` operations (yielding a **43–57× speedup** in `SciDeflate`).
3. **Never use `mmap`/`munmap` (`w_array_new_aligned`) or full-input `calloc` for transient per-call buffers**: Kernel virtual-memory page faults and TLB shootdowns cost 5–10× more than the actual compute kernel on medium-sized inputs (16 KB – 1 MB). Stream blocks in-place and use stack tail buffers or user-space allocations.
4. **Exploit data-parallel algorithms and hardware instructions**: Replacing $O(N \log N)$ comparison sorts with 8-byte prefix LSD radix sort (13× speedup on strings) and serial `CRC32` chains with 4-way parallel `CRC32` + `PMULL` carryless folding (2.92× speedup, 33.15 GB/s) turns standard library calls into hardware-saturating kernels.
