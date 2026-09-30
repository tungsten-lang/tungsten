# Start schemes of the tasks: the standard algorithm, or a named seed.
use core/file
use core/crypto/sha256
use ../composition/packed
use tables

+ Start
  # MFW1 text of the standard algorithm for n x m x p: one term per (i, j, k)
  # with A[i][j], B[j][k] and C[i][k] as the three factors.
  -> .standard(n, m, p) (i64 i64 i64)
    stride = ffpk_stride(n, m, p) ## i64
    rank = n * m * p ## i64
    data = i64[3 * stride * rank]
    t = 0 ## i64
    i = 0 ## i64
    while i < n
      j = 0 ## i64
      while j < m
        k = 0 ## i64
        while k < p
          u = i * m + j ## i64
          v = j * p + k ## i64
          w = i * p + k ## i64
          data[(3 * t) * stride + u / 32] = 1 << (u % 32)
          data[(3 * t + 1) * stride + v / 32] = 1 << (v % 32)
          data[(3 * t + 2) * stride + w / 32] = 1 << (w % 32)
          t += 1
          k += 1
        j += 1
      i += 1
    ffpk_canonicalize(data, data.size, rank, stride)
    ffpk_blob(data, rank, n, m, p)

  # The MFW1 text of the start scheme of a task.
  -> .text(bench, task)
    return Start.standard(task.n, task.m, task.p) if task.standard?
    path = bench.seed_path(task.start)
    text = read_file(path)
    raise "cannot read seed " + path if text == nil
    expected = bench.seed_row(task.start)["sha256"]
    raise "seed " + task.start + " does not match its sha256" if Crypto:SHA256.hexdigest(text) != expected
    text

  # The rank of an MFW1 text (its header).
  -> .rank(text)
    text.split("\n")[0].split(" ")[4].to_i
