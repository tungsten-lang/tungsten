# core/gzip.w against the metaflip release data: parity, decode timing and
# compression of every tensor, next to the Python originals (gzip_bench.py).
#
#   gzip_bench check LIST.tsv                  decode every row and compare it byte for
#                                              byte and by SHA-256 with the corpus tensor
#   gzip_bench time LIST.tsv \[RUNS\]            median decode time of the whole list and of
#                                              the 20 largest distinct tensors (default 5 runs)
#   gzip_bench compress LIST.tsv LEVEL OUTDIR  gzip every distinct tensor to OUTDIR/<sha256>.gz
#
# LIST.tsv has one row per .mfw.gz.b64 file: b64 path, tensor SHA-256, path of
# the plain MFW1 tensor (the port corpus), bundle name; `gzip_bench.py list`
# writes it from the release bundles and the committed certificates.  Decoding
# means Base64 text -> gunzip with the CRC-32 and size checks, files already in
# memory, as in the Python timing.  Build with `tungsten -o gzip_bench
# spec/gzip_bench.w --release`; timings from a plain run are not comparable.
use core/digest

-> now
  ccall_nobox("__w_clock_ns_raw") ## i64

-> rows_of(path)
  rows = []
  read_file(path).split("\n").each -> (line)
    rows.push(line.split("\t")) if line.size > 0
  rows

-> same_bytes(a, b)
  return false if a.size != b.size
  i = 0 ## i64
  n = a.size ## i64
  while i < n
    return false if a[i] != b[i]
    i += 1
  true

-> check(rows)
  agree = 0
  decoded = 0
  i = 0
  while i < rows.size
    out = Gzip.decode_b64(read_file(rows[i][0]))
    want = read_file_bytes(rows[i][2])
    decoded += out.size
    if same_bytes(out, want) && Digest.sha256(out) == rows[i][1]
      agree += 1
    else
      << "MISMATCH " + rows[i][0]
    Gzip.__release(out)
    Gzip.__release(want)
    i += 1
  << "check: " + agree.to_s + " of " + rows.size.to_s + " files decode to the corpus tensor (" + decoded.to_s + " bytes)"
  agree == rows.size

# Median of the n numbers in xs (xs is sorted in place).
-> median(xs)
  xs.sort!
  xs[xs.size / 2]

-> time(rows, runs)
  texts = []
  sizes = i64[rows.size]
  i = 0
  while i < rows.size
    texts.push(read_file(rows[i][0]))
    out = Gzip.decode_b64(texts[i])
    sizes[i] = out.size
    Gzip.__release(out)
    i += 1
  per_file = i64[rows.size * runs]
  totals = i64[runs]
  r = 0
  while r < runs
    whole = 0 ## i64
    i = 0
    while i < rows.size
      t0 = now() ## i64
      out = Gzip.decode_b64(texts[i])
      t1 = now() ## i64
      Gzip.__release(out)
      per_file[i * runs + r] = t1 - t0
      whole += t1 - t0
      i += 1
    totals[r] = whole
    r += 1
  total_bytes = 0 ## i64
  i = 0
  while i < rows.size
    total_bytes += sizes[i]
    i += 1
  mid = median(totals) ## i64
  << "whole list: " + rows.size.to_s + " files, " + total_bytes.to_s + " bytes, median of " + runs.to_s + " runs " + (mid / 1000).to_s + " us = " + (total_bytes * 1000 / mid).to_s + " MB/s"
  << "rank\tbytes\tus\tMB/s\tfile"
  taken = i64[rows.size]
  rank = 1
  while rank <= 20
    best = -1
    i = 0
    while i < rows.size
      best = i if taken[i] == 0 && (best < 0 || sizes[i] > sizes[best])
      i += 1
    j = 0
    while j < rows.size
      taken[j] = 1 if rows[j][1] == rows[best][1]
      j += 1
    samples = i64[runs]
    r = 0
    while r < runs
      samples[r] = per_file[best * runs + r]
      r += 1
    ns = median(samples) ## i64
    << rank.to_s + "\t" + sizes[best].to_s + "\t" + (ns / 1000).to_s + "\t" + (sizes[best] * 1000 / ns).to_s + "\t" + rows[best][0].split("/").last
    rank += 1

# One .gz per distinct tensor; the time is that of Gzip.compress alone.
-> compress(rows, level, outdir)
  seen = {}
  count = 0
  raw_total = 0
  packed_total = 0
  ns = 0 ## i64
  i = 0
  while i < rows.size
    sha = rows[i][1]
    if !seen.has_key?(sha)
      seen[sha] = true
      raw = read_file_bytes(rows[i][2])
      t0 = now() ## i64
      packed = Gzip.compress(raw, level)
      t1 = now() ## i64
      ns += t1 - t0
      write_file_bytes(outdir + "/" + sha + ".gz", packed)
      count += 1
      raw_total += raw.size
      packed_total += packed.size
      Gzip.__release(raw)
      Gzip.__release(packed)
    i += 1
  << "compress: " + count.to_s + " tensors, " + raw_total.to_s + " -> " + packed_total.to_s + " bytes at level " + level.to_s + " in " + (ns / 1000000).to_s + " ms = " + (raw_total * 1000 / ns).to_s + " MB/s"

args = argv()
if args.size < 2
  << "usage: gzip_bench check LIST.tsv | time LIST.tsv \[RUNS\] | compress LIST.tsv LEVEL OUTDIR"
  exit(2)
rows = rows_of(args[1])
if args[0] == "check"
  exit(1) if !check(rows)
elsif args[0] == "time"
  time(rows, args.size > 2 ? args[2].to_i : 5)
elsif args[0] == "compress" && args.size == 4
  compress(rows, args[2].to_i, args[3])
else
  << "usage: gzip_bench check LIST.tsv | time LIST.tsv \[RUNS\] | compress LIST.tsv LEVEL OUTDIR"
  exit(2)
