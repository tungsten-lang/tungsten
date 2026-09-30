#!/usr/bin/env python3
"""The Python side of spec/gzip_bench.w: the list of release files, the decode
timing of the originals (base64 + gzip) and the check of what Tungsten's
compressor wrote.

  gzip_bench.py list WORK REPO > LIST.tsv
      one row per .mfw.gz.b64 file: b64 path, tensor SHA-256, path of the plain
      tensor (WORK/port-corpus/mfw/<sha256>.mfw), bundle.  WORK is the record
      hunt work directory (release-0929/ and port-corpus/ below it): the rows of
      the four bundles' manifest.json (1,087 files) and the committed
      certificates named by gf2-campaign-records/records.tsv (102 files, paths
      relative to REPO).
  gzip_bench.py time LIST.tsv [RUNS]
      median decode time (b64decode(validate=True) + gzip.decompress, files in
      memory) of the whole list and of the 20 largest distinct tensors, in the
      format of `gzip_bench time`.
  gzip_bench.py compress LIST.tsv LEVEL
      gzip.compress(mtime=0) of every distinct tensor, timed like `gzip_bench
      compress`, for comparison.
  gzip_bench.py verify LIST.tsv OUTDIR
      every OUTDIR/<sha256>.gz written by `gzip_bench compress` must inflate, with
      Python's gzip, to the corpus tensor; prints the sizes next to zlib's.
"""
import base64
import csv
import gzip
import json
import os
import statistics
import sys
import time

BUNDLES = ("gf2-block47-certificates-2026-07", "gf2-closure-products",
           "gf2-public-ternary-walks-2026-09-26", "gf2-searched-records")
COMMITTED = "bits/tungsten-metaflip (committed certificate)"


def make_list(work, repo):
    release = os.path.join(work, "release-0929")
    for bundle in BUNDLES:
        with open(os.path.join(release, bundle, "manifest.json")) as f:
            for row in json.load(f)["rows"]:
                yield (os.path.join(release, bundle, row["file"]), row["sha256"], bundle)
    with open(os.path.join(release, "gf2-campaign-records", "records.tsv")) as f:
        for row in csv.DictReader(f, delimiter="\t"):
            if row["asset"] == COMMITTED:
                yield (os.path.join(repo, row["file"]), row["tensor_sha256"], "committed")


def read_list(path):
    with open(path) as f:
        return [line.rstrip("\n").split("\t") for line in f if line.strip()]


def decode(text):
    return gzip.decompress(base64.b64decode(text.replace(b"\n", b""), validate=True))


def timing(rows, runs):
    texts = [open(row[0], "rb").read() for row in rows]
    sizes = [len(decode(text)) for text in texts]
    per_file = [[] for _ in rows]
    totals = []
    for _ in range(runs):
        whole = 0
        for i, text in enumerate(texts):
            start = time.perf_counter_ns()
            decode(text)
            elapsed = time.perf_counter_ns() - start
            per_file[i].append(elapsed)
            whole += elapsed
        totals.append(whole)
    mid = statistics.median_low(totals)
    print(f"whole list: {len(rows)} files, {sum(sizes)} bytes, median of {runs} runs "
          f"{mid // 1000} us = {sum(sizes) * 1000 // mid} MB/s")
    print("rank\tbytes\tus\tMB/s\tfile")
    firsts = {}
    for i, row in enumerate(rows):
        firsts.setdefault(row[1], i)          # a tensor kept as a certificate is listed twice
    for rank, i in enumerate(sorted(firsts.values(), key=lambda i: -sizes[i])[:20], 1):
        ns = statistics.median_low(per_file[i])
        print(f"{rank}\t{sizes[i]}\t{ns // 1000}\t{sizes[i] * 1000 // ns}\t{os.path.basename(rows[i][0])}")


def compress(rows, level):
    seen, raw_total, packed_total, ns = set(), 0, 0, 0
    for row in rows:
        if row[1] in seen:
            continue
        seen.add(row[1])
        with open(row[2], "rb") as f:
            raw = f.read()
        start = time.perf_counter_ns()
        packed = gzip.compress(raw, level, mtime=0)
        ns += time.perf_counter_ns() - start
        raw_total += len(raw)
        packed_total += len(packed)
    print(f"compress: {len(seen)} tensors, {raw_total} -> {packed_total} bytes at level {level} "
          f"in {ns // 1000000} ms = {raw_total * 1000 // ns} MB/s")


def verify(rows, outdir):
    seen, good, raw_total, mine, ref9, ref6 = set(), 0, 0, 0, 0, 0
    worst = (0.0, "")
    for row in rows:
        if row[1] in seen:
            continue
        seen.add(row[1])
        with open(row[2], "rb") as f:
            raw = f.read()
        with open(os.path.join(outdir, row[1] + ".gz"), "rb") as f:
            packed = f.read()
        good += gzip.decompress(packed) == raw
        raw_total += len(raw)
        mine += len(packed)
        nine = len(gzip.compress(raw, 9, mtime=0))
        ref9 += nine
        ref6 += len(gzip.compress(raw, 6, mtime=0))
        worst = max(worst, (len(packed) / nine, row[1][:8]))
    print(f"verify: {good} of {len(seen)} files inflate with Python's gzip.decompress to the corpus tensor")
    print(f"sizes: raw {raw_total}, tungsten {mine}, zlib level 9 {ref9}, zlib level 6 {ref6}; "
          f"tungsten/zlib-9 = {mine / ref9:.4f} (worst file {worst[0]:.4f} {worst[1]})")
    return good == len(seen)


def main(argv):
    if len(argv) == 3 and argv[0] == "list":
        for row in make_list(argv[1], argv[2]):
            print("\t".join((row[0], row[1], os.path.join(argv[1], "port-corpus", "mfw", row[1] + ".mfw"), row[2])))
    elif len(argv) in (2, 3) and argv[0] == "time":
        timing(read_list(argv[1]), int(argv[2]) if len(argv) == 3 else 5)
    elif len(argv) == 3 and argv[0] == "compress":
        compress(read_list(argv[1]), int(argv[2]))
    elif len(argv) == 3 and argv[0] == "verify":
        return 0 if verify(read_list(argv[1]), argv[2]) else 1
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
