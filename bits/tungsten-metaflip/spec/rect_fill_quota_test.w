use ../lib/metaflip/rect/portfolio

failures = 0 ## i64
-> fill_expect(label, ok) (String bool) i64
  if ok
    return 0
  << "FAIL rect fill: " + label
  1

failures += fill_expect("single mode preserves one round", ffrpo_fill_quota(10, 100, 10000, 64, 0, 0) == 1)
failures += fill_expect("single cold start has no estimate", ffrpo_fill_quota(10, 100, 0, 64, 1, 0) == 0)
failures += fill_expect("batch amortizes short rounds", ffrpo_fill_quota(10, 100, 10000, 64, 0, 1) == 64)
failures += fill_expect("half of short remaining interval", ffrpo_fill_quota(10, 100, 500, 64, 0, 1) == 20)
failures += fill_expect("one second predicted work cap", ffrpo_fill_quota(25, 100, 10000, 1000, 0, 1) == 40)
failures += fill_expect("cold GPU bounded provisional window", ffrpo_fill_quota(10, 100, 1100, 64, 1, 1) == 50)
failures += fill_expect("cold GPU cannot extend hard stop", ffrpo_fill_quota(10, 100, 120, 64, 1, 1) == 1)
failures += fill_expect("no fill at or beyond deadline", ffrpo_fill_quota(1, 100, 100, 64, 1, 1) == 0 && ffrpo_fill_quota(1, 100, 99, 64, 0, 1) == 0)
failures += fill_expect("equality preserves strict fit", ffrpo_fill_quota(10, 100, 110, 64, 0, 1) == 0)
failures += fill_expect("unknown duration rejects", ffrpo_fill_quota(0, 100, 10000, 64, 1, 1) == 0)
failures += fill_expect("one round floor", ffrpo_fill_quota(99, 100, 200, 64, 0, 1) == 1)
failures += fill_expect("base and fill quota counts", ffrpo_segment_rounds(64, 64, 0) == 64 && ffrpo_segment_rounds(20, 20, 0) == 20)
failures += fill_expect("partial live fill counts observed rounds", ffrpo_segment_rounds(20, 7, 0) == 7)
failures += fill_expect("terminal publication is not a search round", ffrpo_segment_rounds(20, 7, 1) == 6 && ffrpo_segment_rounds(20, 21, 1) == 20)
failures += fill_expect("stop before first round", ffrpo_segment_rounds(20, 1, 1) == 0)
failures += fill_expect("status cannot exceed launch quota", ffrpo_segment_rounds(20, 21, 0) == 20)

# Deterministic boundaries: never launch more rounds than the base quota;
# predicted fill duration remains below the available window.
avg = 1 ## i64
while avg < 100
  remain = 0 ## i64
  while remain < 2200
    rounds = ffrpo_fill_quota(avg, 1000, 1000 + remain, 64, 0, 1) ## i64
    failures += fill_expect("quota range", rounds >= 0 && rounds <= 64)
    if rounds > 0
      failures += fill_expect("strict predicted fit", rounds * avg < remain)
      failures += fill_expect("bounded predicted duration", rounds == 1 || rounds * avg <= 1000)
    remain += 17
  avg += 3
if failures != 0
  exit(1)
<< "PASS bounded rectangular fill batches and partial-segment accounting"
