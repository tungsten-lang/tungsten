# Deterministic DecisionTree training/prediction benchmark.
#
# Compile and run from the repository root:
#   bin/tungsten compile bits/tungsten-koala/benchmarks/decision_tree_speed.w \
#     --out /tmp/koala-decision-tree-speed
#   /tmp/koala-decision-tree-speed
#
# This is a scaling probe, not a one-shot marketing number. The generated
# 1,200 x 12 classification table has repeatable nonlinear signal and enough
# distinct values to exercise the split-search hot path. Report node count and
# accuracy beside elapsed time so an accidentally trivial tree cannot look
# fast.

use koala

-> tree_benchmark_rows(n, width)
  rows = []
  labels = []
  i = 0
  while i < n
    row = []
    j = 0
    while j < width
      row.push((i * (37 + j * 2) + j * 101 + i * j * 3) % 1009)
      j += 1
    signal = row[0] + row[3] - row[5]
    label = 0
    label = 1 if signal > 450
    label = 2 if row[7] < 200 && row[1] > 600
    rows.push(row)
    labels.push(label)
    i += 1
  { rows: rows, labels: labels }

fixture = tree_benchmark_rows(1200, 12)
x = fixture[:rows]
y = fixture[:labels]

started = ccall("__w_clock_ms")
model = nil
2.times -> (repeat)
  model = DecisionTreeClassifier.new(8, 2, 2, :gini)
  model.fit(x, y)
train_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
checksum = 0
25.times -> (repeat)
  preds = model.predict(x)
  preds.each -> (label)
    checksum += label
predict_ms = ccall("__w_clock_ms") - started

<< "decision_tree_train_ms," + train_ms.to_s
<< "decision_tree_predict_ms," + predict_ms.to_s
<< "decision_tree_nodes," + model.node_count.to_s
<< "decision_tree_accuracy," + model.score(x, y).to_s
<< "decision_tree_checksum," + checksum.to_s
