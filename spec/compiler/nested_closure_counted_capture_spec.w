# Regression (block-capture flush): a machine-int local counted inside one
# block closure (`npos`) and then CAPTURED into a second, nested-closure loop
# must keep its live value at capture time.
#
# The block-capture "always flush" path used to synthesize a flush value even
# when the captured variable ALREADY had a frame slot holding its live value.
# For `npos` (materialized by the first `each`, then re-captured) it recovered
# the variable's stale *literal initializer* (`npos = 0`) and flushed that 0
# back into the slot, clobbering the counted value of 2. `if npos > 0` then
# read false and `r` kept its `1.to_f` initializer, so recall came out
# 1,1,1,1 instead of 0,0,0.5,1. The inner-loop-accumulated `tp` plus the
# captured counter `npos` being live raw ints across nested closures is the
# trigger; a method-call source (`Repro.identity`) for the outer loop and a
# non-literal denominator (`npf`) are required. Interpreted output is the
# oracle (matches sklearn's precision_recall_curve).
#
# Run: bin/tungsten -o /tmp/nccc spec/compiler/nested_closure_counted_capture_spec.w && /tmp/nccc

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got + " want " + want

+ Repro
  -> .identity/1
    @1
  -> .recalls
    scores = [9.to_f, 8.to_f, 2.to_f, 1.to_f]
    actual = [0, 0, 1, 1]
    npos = 0
    actual.each -> (a)
      npos = npos + 1 if a == 1
    npf = npos.to_f
    desc = Repro.identity(scores)
    rec = []
    prec = []
    desc.each -> (t)
      tp = 0
      fp = 0
      i = 0
      scores.each -> (s)
        if s.to_f >= t
          if actual[i] == 1
            tp = tp + 1
          else
            fp = fp + 1
        i = i + 1
      p = 0.to_f
      p = tp.to_f / (tp + fp).to_f if (tp + fp) > 0
      r = 1.to_f
      r = tp.to_f / npf if npos > 0
      prec.push(p)
      rec.push(r)
    rec

check("nested_closure_counted_capture.recall", Repro.recalls.join(","), "0,0,0.5,1")
