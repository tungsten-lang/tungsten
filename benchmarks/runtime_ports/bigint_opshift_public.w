# True-public benchmark for the bigint `<<` and `>>` source arms. Same
# binary A/B via TUNGSTEN_BIGINT_SRC_OPS (unset = source, 0 = C pinned).
#
# Strata (per op; argv mode selects shl or shr rows):
#   one13    — 1-limb receiver, k=13 (source: result demotes to inline i48)
#   oneheap  — 1-limb receiver, k=13 (control: result remains a heap BigInt)
#   oneneg13 — negative 1-limb receiver, k=13 (candidate i48 demotion)
#   onenegheap — negative 1-limb receiver, k=13 (control: result stays heap)
#   four13   — 4-limb, k=13 (sub-limb funnel)
#   four64   — 4-limb, k=64 (bit-aligned word path, s == 0)
#   sf13     — 64-limb, k=13
#   thirtytwo13 — 32-limb fixed-rung control, k=13
#   thirtythree13 — 33-limb, k=13 (first width above fixed C rungs)
#   thirtythree-trim13 — 33 limbs whose shifted top vanishes
#   forty13  — 40-limb, k=13
#   sixtyfive13 — 65-limb, k=13
#   eighty13 — 80-limb, k=13
#   ninetysix13 — 96-limb, k=13
#   ninetyseven13 — 97-limb C-retained seam control, k=13
#   onetwentyeight13 — 128-limb, k=13
#   onesixty13 — 160-limb, k=13
#   oneninetytwo13 — 192-limb, k=13
#   twotwentythree13 — 223-limb retained-band interior, k=13
#   twotwentyfour13 — 224-limb, k=13
#   twotwentyfive13 — 225-limb C-retained seam control, k=13
#   wide13   — 256-limb C-retained control, k=13
#   max13    — 4096-limb, k=13 (wide C-retained control)
#   overband13 — 4097-limb, k=13 (adjacent C-retained control)
#   sf200    — 64-limb, k=200 (w=3, s=8)
#   big1000  — 256-limb, k=1000
#   neg      — 4-limb negative receiver, k=13 (control: C keeps negatives)
#   overpos  — 4-limb positive receiver, k=1000 (result is inline zero)
#   overneg  — 4-limb negative receiver, k=1000 (result is inline minus one)
#   negkpos  — 4-limb positive receiver, k=-1000 (`<<` overshift mirror)
#   negkneg  — 4-limb negative receiver, k=-1000 (`<<` overshift mirror)
#   zero     — 4-limb positive receiver, k=0 (identity + alias handoff)
#   zeroneg  — 4-limb negative receiver, k=0 (identity + alias handoff)
#   fourtail13 — 4-limb positive, k=205 (top-limb funnel demotes to i48)
#   fourtail64 — 4-limb positive, k=192 (aligned top limb demotes to i48)
#   fourtailneg13 — negative mirror with sticky-bit rounding
#   fourtailneg64 — aligned negative mirror with lower-limb sticky bits
#   fourneg13 — ordinary negative 4-limb fallback control, k=13
#   sftailneg13 — negative 64-limb top-funnel demotion, low limb proves sticky
#   sftailneg64 — aligned negative 64-limb demotion, low limb proves sticky
#   sfneg13 — ordinary negative 64-limb fallback control, k=13

CORPUS_SIZE = 8
CORPUS_MASK = CORPUS_SIZE - 1

-> consume_low_byte(value)
  ccall("w_leafpub_consume_low_byte", value)

-> consume_alias_low_byte(value)
  ccall("w_leafpub_consume_alias_low_byte", value)

-> thread_cpu_ns
  ccall("w_leafpub_thread_cpu_ns")

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> one_limb_value(k)
  1125899906842624 + k * 2 + 1

-> build_receivers(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    if stratum == "one13"
      v = one_limb_value(i * 3)
    elsif stratum == "oneneg13"
      v = 0 - one_limb_value(i * 3)
    elsif stratum == "oneheap" || stratum == "onenegheap"
      v = (1 << 63) + i * 2 + 1
    elsif stratum == "fourtail13" || stratum == "fourtailneg13"
      v = (1 << 250) + (1 << 130) + 3 + i * 2
    elsif stratum == "fourtail64" || stratum == "fourtailneg64"
      v = (1 << 192) + (1 << 100) + 3 + i * 2
    elsif stratum == "sftailneg13"
      v = (1 << 4090) + (1 << 2000) + 3 + i * 2
    elsif stratum == "sftailneg64"
      v = (1 << 4032) + (1 << 2000) + 3 + i * 2
    elsif stratum == "four13" || stratum == "four64" || stratum == "fourneg13" || stratum == "neg" || stratum == "overpos" || stratum == "overneg" || stratum == "negkpos" || stratum == "negkneg" || stratum == "zero" || stratum == "zeroneg"
      v = 10 ** 76 + 3 + i * 2
    elsif stratum == "thirtytwo13"
      v = (1 << 2047) + (1 << 1000) + 11 + i * 2
    elsif stratum == "thirtythree13"
      v = (1 << 2111) + (1 << 1000) + 11 + i * 2
    elsif stratum == "thirtythree-trim13"
      v = (1 << 2048) + (1 << 1000) + 11 + i * 2
    elsif stratum == "forty13"
      v = (1 << 2559) + (1 << 1200) + 11 + i * 2
    elsif stratum == "sf13" || stratum == "sf200" || stratum == "sfneg13"
      v = 10 ** 1232 + 11 + i * 2
    elsif stratum == "sixtyfive13"
      v = (1 << 4159) + (1 << 2000) + 11 + i * 2
    elsif stratum == "eighty13"
      v = (1 << 5119) + (1 << 2500) + 11 + i * 2
    elsif stratum == "ninetysix13"
      v = (1 << 6143) + (1 << 3000) + 11 + i * 2
    elsif stratum == "ninetyseven13"
      v = (1 << 6207) + (1 << 3000) + 11 + i * 2
    elsif stratum == "onetwentyeight13"
      v = (1 << 8191) + (1 << 4000) + 11 + i * 2
    elsif stratum == "onesixty13"
      v = (1 << 10239) + (1 << 5000) + 11 + i * 2
    elsif stratum == "oneninetytwo13"
      v = (1 << 12287) + (1 << 6000) + 11 + i * 2
    elsif stratum == "twotwentythree13"
      v = (1 << 14271) + (1 << 7000) + 11 + i * 2
    elsif stratum == "twotwentyfour13"
      v = (1 << 14335) + (1 << 7000) + 11 + i * 2
    elsif stratum == "twotwentyfive13"
      v = (1 << 14399) + (1 << 7000) + 11 + i * 2
    elsif stratum == "wide13"
      v = (1 << 16383) + (1 << 8000) + 11 + i * 2
    elsif stratum == "max13"
      v = (1 << 262143) + (1 << 131000) + 11 + i * 2
    elsif stratum == "overband13"
      v = (1 << 262207) + (1 << 131000) + 11 + i * 2
    else
      v = 10 ** 4928 + 11 + i * 2
    if stratum == "neg" && (i & 1) == 1
      v = 0 - v
    if stratum == "overneg" || stratum == "negkneg" || stratum == "zeroneg"
      v = 0 - v
    if stratum == "onenegheap"
      v = 0 - v
    if stratum == "fourtailneg13" || stratum == "fourtailneg64"
      v = 0 - v
    if stratum == "fourneg13"
      v = 0 - v
    if stratum == "sftailneg13" || stratum == "sftailneg64" || stratum == "sfneg13"
      v = 0 - v
    values.push(v)
    i += 1
  values

-> stratum_k(stratum)
  if stratum == "four64"
    return 64
  if stratum == "sf200"
    return 200
  if stratum == "fourtail13" || stratum == "fourtailneg13"
    return 205
  if stratum == "fourtail64" || stratum == "fourtailneg64"
    return 192
  if stratum == "sftailneg13"
    return 4045
  if stratum == "sftailneg64"
    return 4032
  if stratum == "big1000" || stratum == "overpos" || stratum == "overneg"
    return 1000
  if stratum == "negkpos" || stratum == "negkneg"
    return -1000
  if stratum == "zero" || stratum == "zeroneg"
    return 0
  13

-> run_correctness
  strata = ["one13", "oneheap", "oneneg13", "onenegheap", "four13", "four64", "fourneg13", "fourtail13", "fourtail64", "fourtailneg13", "fourtailneg64", "thirtytwo13", "thirtythree13", "thirtythree-trim13", "forty13", "sf13", "sixtyfive13", "eighty13", "ninetysix13", "ninetyseven13", "onetwentyeight13", "onesixty13", "oneninetytwo13", "twotwentythree13", "twotwentyfour13", "twotwentyfive13", "wide13", "max13", "overband13", "sf200", "sfneg13", "sftailneg13", "sftailneg64", "big1000", "neg", "overpos", "overneg", "negkpos", "negkneg", "zero", "zeroneg"]
  s = 0
  while s < strata.size
    stratum = strata[s]
    receivers = build_receivers(stratum)
    k = stratum_k(stratum)
    i = 0
    while i < CORPUS_SIZE
      x = receivers[i]
      if k < 0
        check_value("negative_count [stratum]/[i]", (x << k).to_s(), (x >> (0 - k)).to_s())
      else
        l = x << k
        check_value("shl_inverse [stratum]/[i]", (l >> k).to_s(), x.to_s())
        r = x >> k
        check_value("shr_rebuild [stratum]/[i]", ((r << k) + (x - (r << k))).to_s(), x.to_s())
      i += 1
    s += 1
  << "correctness: ok (shift identities, [strata.size] strata)"

-> time_shl(receivers, k, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    j = i & CORPUS_MASK
    checksum += consume_low_byte(receivers[j] << k)
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_shr(receivers, k, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    j = i & CORPUS_MASK
    checksum += consume_low_byte(receivers[j] >> k)
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_shl_alias(receivers, k, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    j = i & CORPUS_MASK
    checksum += consume_alias_low_byte(receivers[j] << k)
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_shr_alias(receivers, k, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    j = i & CORPUS_MASK
    checksum += consume_alias_low_byte(receivers[j] >> k)
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(op, stratum, iters, warmup)
  receivers = build_receivers(stratum)
  k = stratum_k(stratum)
  if op == "shl"
    if k == 0
      time_shl_alias(receivers, k, warmup)
      result = time_shl_alias(receivers, k, iters)
    else
      time_shl(receivers, k, warmup)
      result = time_shl(receivers, k, iters)
  else
    if k == 0
      time_shr_alias(receivers, k, warmup)
      result = time_shr_alias(receivers, k, iters)
    else
      time_shr(receivers, k, warmup)
      result = time_shr(receivers, k, iters)
  << "RESULT|[op]-[stratum]|[result[0]]|[iters]|[result[1]]"

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

if mode != "shl" && mode != "shr"
  << "mode must be check, shl or shr"
  exit(2)

stratum = args_v.size() > 1 ? args_v[1] : "four13"
iters = args_v.size() > 2 ? args_v[2].to_i : 2_000_000
warmup = args_v.size() > 3 ? args_v[3].to_i : iters / 10
if iters <= 0
  << "iterations must be positive"
  exit(2)
run_bench(mode, stratum, iters, warmup)
