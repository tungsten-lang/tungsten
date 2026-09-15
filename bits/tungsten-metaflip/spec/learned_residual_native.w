# Native oracle for the independent Python residual/tensor checker.
use ../tools/learned_residual/native/search

if ARGV.size() != 2
  << "usage: learned_residual_native MODEL CASES"
  exit(2)
model = f64[517]
if fflr_load(ARGV[0], model) != 1
  << "INVALID_MODEL"
  exit(2)
lines = read_file(ARGV[1]).strip().split("\n")
row = 0 ## i64
while row < lines.size()
  fields = lines[row].split(" ")
  widths = i64[3]
  dims = i64[3]
  i = 0 ## i64
  while i < 3
    widths[i] = fields[i].to_i()
    i += 1
  count = fields[3].to_i() ## i64
  limit = fields[4].to_i() ## i64
  budget = fields[5].to_i() ## i64
  terms = i64[18]
  i = 0
  while i < 3*count
    terms[i] = fields[6+i].to_i()
    i += 1
  bases = i64[12]
  piv = i64[189]
  codes = i64[189]
  if fflr_compress(terms, count, widths, dims, bases, piv, codes) != 1
    << "UNSUPPORTED"
  else
    core = fflr_core(terms, count, widths, dims, piv, codes) ## i64
    features = f64[18]
    rows = i64[4]
    pr = i64[16]
    mr = i64[4]
    cache = i64[327680]
    if core != 0
      z = fflr_features(core, dims, features, rows, pr, mr, cache) ## i64
    score = fflr_score(features, model) ## f64
    body = "CASE " + dims[0].to_s() + " " + dims[1].to_s() + " " + dims[2].to_s() + " " + core.to_s() + " " + score.to_s()
    i = 0
    while i < 18
      body = body + " " + features[i].to_s()
      i += 1
    i = 0
    while i < 12
      body = body + " " + bases[i].to_s()
      i += 1
    out = i64[18]
    stats = i64[5]
    completed = fflr_search(core, dims, limit, model, out, stats, budget, 200, "", row+1) ## i64
    body = body + " " + completed.to_s() + " " + stats[0].to_s() + " " + stats[4].to_s()
    i = 0
    while i < completed
      axis = 0 ## i64
      while axis < 3
        body = body + " " + fflr_lift(out[3*i+axis], axis, bases).to_s()
        axis += 1
      i += 1
    << body
  row += 1
