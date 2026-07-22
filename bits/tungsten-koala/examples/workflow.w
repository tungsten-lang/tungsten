# Train/test workflow — the full koala loop in one runnable file:
# inline DataFrame -> seeded Splitter -> Imputer + Scaler +
# LinearRegression Pipeline -> fit on train -> R² on held-out test.
#
# Run it on either engine from the repo root:
#   bin/tungsten bits/tungsten-koala/examples/workflow.w
#   bin/tungsten -o /tmp/workflow bits/tungsten-koala/examples/workflow.w && /tmp/workflow
#
# The output is deterministic BY DESIGN — Splitter's seeded shuffle is
# a built-in MINSTD generator, identical on both engines — so this
# example is self-checking: it compares its own transcript against the
# expected text below and exits 1 on any mismatch (chosen over a
# separate spec so the runnable artifact carries its own proof).
#
# House rules on display: \[...\] is escaped in string literals (bare
# brackets interpolate). Float#to_s prints the full f64, so the expected
# transcript below carries the exact rendered digits — deterministic and
# byte-identical on both engines.

use koala

lines = []

# 1. A small inline frame: two numeric features with a couple of
#    missing cells, plus the target as a third column so ONE split
#    keeps features and target row-aligned. Underlying truth:
#    price = 3 + 2*sqft + rooms.
df = DataFrame.new([
  [:sqft,  [8, 6, nil, 11, 5, 9, 12, 7, 10, 6]],
  [:rooms, [2, 1, 3, 3, nil, 2, 4, 2, 3, 1]],
  [:price, [21, 16, 20, 28, 15, 23, 31, 19, 26, 16]]
])
lines.push("frame " + df.row_count.to_s + " rows: " + df.column_names.join("/"))

# 2. Seeded 30% hold-out — same seed, same split, on both engines.
pair = Splitter.train_test(df, 30, 42)
train = pair[0]
test = pair[1]
lines.push("split (seed 42): train " + train.row_count.to_s + " rows, test " + test.row_count.to_s + " rows")

# 3. Features and target, extracted AFTER the split so they stay aligned.
x_train = train.select_columns([:sqft, :rooms])
y_train = train.column_values(:price)
x_test = test.select_columns([:sqft, :rooms])
y_test = test.column_values(:price)

# 4. Impute -> scale -> regress as one Pipeline. fit learns the fill
#    means and the scaling mean/std from TRAIN ONLY, then fits the
#    estimator tail on the transformed features.
pipe = Pipeline.new([Imputer.new(:mean), Scaler.new(:standard), LinearRegression.new])
pipe.fit(x_train, y_train)
lr = pipe[2]
lines.push("intercept " + lr.intercept.to_s)
lines.push("coefficients " + lr.coefficients.to_s)

# 5. Score. Test rows ride the SAME fitted imputer/scaler (training
#    statistics — never their own) before the estimator sees them.
lines.push("train R2 " + pipe.score(x_train, y_train).to_s)
lines.push("test R2 " + pipe.score(x_test, y_test).to_s)

out = lines.join("\n")
<< out

# --- Self-check: the transcript above is the contract. ---
# Verified identical on both engines (interpreted and compiled).
# Why these numbers: seed 42 shuffles 10 rows to order
# [0,1,4,3,8,9,7,5,6,2] — train takes the first 7, test rows {5,6,2}.
# Train's one missing cell (row 4's rooms) imputes to the train mean
# 12/6 = 2, which happens to equal the true value, so train stays
# exactly on the price = 3 + 2*sqft + rooms plane: train R² = 1. Test
# row 2's missing sqft imputes to 53/7 ≈ 7.571 (true value 7), pulling
# that prediction to ≈ 21.143 against y = 20 — hence test R² =
# 1 - (1.143²)/64.667 ≈ 0.979802. The intercept is the train-price
# mean 141/7 ≈ 20.143 (standardized features center at zero).
expected_lines = []
expected_lines.push("frame 10 rows: sqft/rooms/price")
expected_lines.push("split (seed 42): train 7 rows, test 3 rows")
expected_lines.push("intercept 20.142857142857146")
expected_lines.push("coefficients \[4.4507891221134948, 0.81649658092772703\]")
expected_lines.push("train R2 1")
expected_lines.push("test R2 0.97980223017041856")
expected = expected_lines.join("\n")
if out != expected
  << "WORKFLOW: MISMATCH — expected transcript:"
  << expected
  exit(1)
<< "WORKFLOW: OK — transcript matched, deterministic on both engines"
