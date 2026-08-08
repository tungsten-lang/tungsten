# KNN classifier neighbour-selection scaling probe (compiled only).
#
# Compile and run from the repository root:
#   bin/tungsten compile bits/tungsten-koala/benchmarks/knn_selection_speed.w \
#     --out /tmp/koala-knn-selection-speed
#   /tmp/koala-knn-selection-speed
#
# The wide-k case is the useful signal: distance calculation is identical for
# every k, while neighbour bookkeeping should scale linearly rather than with
# repeated membership scans. Checksums keep timing changes tied to identical
# predictions.

use koala

-> knn_benchmark_training(n)
  rows = []
  labels = []
  i = 0
  while i < n
    rows.push([
      (i * 37) % 1009,
      (i * 67 + 11) % 1013,
      (i * 97 + 23) % 1019,
      (i * 127 + 41) % 1021
    ])
    labels.push((i * 13 + i / 7) % 5)
    i += 1
  { rows: rows, labels: labels }

-> knn_benchmark_queries(rows, n)
  out = []
  i = 0
  while i < n
    source = rows[(i * 191 + 17) % rows.size]
    out.push([source[0] + 1, source[1] - 1, source[2] + 2, source[3] - 2])
    i += 1
  out

-> run_knn_selection(rows, labels, queries, k, rounds)
  model = KNNClassifier.new(k)
  model.fit(rows, labels)
  model.predict(queries)
  checksum = 0
  started = ccall("__w_clock_ms")
  rounds.times -> (round)
    predictions = model.predict(queries)
    predictions.each -> (label)
      checksum += label
  elapsed = ccall("__w_clock_ms") - started
  { ms: elapsed, checksum: checksum }

fixture = knn_benchmark_training(6000)
queries = knn_benchmark_queries(fixture[:rows], 32)
rounds = 3

[1, 5, 50].each -> (k)
  result = run_knn_selection(fixture[:rows], fixture[:labels], queries, k, rounds)
  << "knn_k_[k]_ms," + result[:ms].to_s
  << "knn_k_[k]_checksum," + result[:checksum].to_s

<< "knn_training_rows," + fixture[:rows].size.to_s
<< "knn_query_rows," + queries.size.to_s
<< "knn_rounds," + rounds.to_s
