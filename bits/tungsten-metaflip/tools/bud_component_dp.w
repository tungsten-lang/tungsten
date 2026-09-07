# Offline exact maximum-weight disjoint-set packing for components of <=16
# vertices. Input is a batch of edge masks/gains, not a tensor certificate.
# Choosing the highest vertex gives dp(S)=max(dp(S-v),gain(E)+dp(S-E)).
# Only the lower half of subsets and the full mask are reachable from the
# full mask. The deterministic charged state count is 2^(n-1).
-> ffcd_state(mask, gains, dp, choices) (i64 i64[] i64[] i64[]) i64
  bit = 1 ## i64
  while (bit << 1) <= mask
    bit = bit << 1
  rest = mask ^ bit ## i64
  best = dp[rest] ## i64
  chosen = 0 ## i64
  subset = rest ## i64
  transitions = 0 ## i64
  while true
    edge = bit | subset ## i64
    gain = gains[edge] ## i64
    transitions += 1
    if gain > 0
      value = gain + dp[rest ^ subset] ## i64
      if value > best
        best = value
        chosen = edge
    if subset == 0
      break
    subset = (subset - 1) & rest
  dp[mask] = best
  choices[mask] = chosen
  transitions

if ARGV.size() != 1
  << "usage: bud_component_dp BATCH_FILE"
  exit(2)
content = read_file(ARGV[0])
if content == nil || content.size() > 64000000
  << "invalid batch file"
  exit(2)
lines = content.strip().split("\n")
jobs = lines[0].to_i() ## i64
if jobs < 1 || jobs > 1024 || jobs.to_s() != lines[0]
  << "invalid job count"
  exit(2)
gains = i64[65536]
dp = i64[65536]
choices = i64[65536]
line = 1 ## i64
job = 0 ## i64
while job < jobs
  if line >= lines.size()
    << "missing component header"
    exit(2)
  fields = lines[line].split(" ")
  line += 1
  if fields.size() != 3
    << "invalid component header"
    exit(2)
  vertices = fields[0].to_i() ## i64
  count = fields[1].to_i() ## i64
  budget = fields[2].to_i() ## i64
  if vertices < 1 || vertices > 16 || vertices.to_s() != fields[0] || count < 0 || count > 65535 || count.to_s() != fields[1] || budget < 1 || budget > 1000000000 || budget.to_s() != fields[2]
    << "invalid component dimensions"
    exit(2)
  size = 1 << vertices ## i64
  half = size >> 1 ## i64
  if half > budget || count >= size || line + count > lines.size()
    << "insufficient state budget or invalid edge count"
    exit(2)
  i = 0 ## i64
  while i < size
    gains[i] = 0
    i += 1
  i = 0
  while i < count
    fields = lines[line].split(" ")
    line += 1
    if fields.size() != 2
      << "invalid edge"
      exit(2)
    mask = fields[0].to_i() ## i64
    gain = fields[1].to_i() ## i64
    if mask < 1 || mask >= size || mask.to_s() != fields[0] || gain < 1 || gain > 1000000000 || gain.to_s() != fields[1]
      << "invalid edge mask or gain"
      exit(2)
    if gains[mask] != 0
      << "duplicate edge mask"
      exit(2)
    gains[mask] = gain
    i += 1
  dp[0] = 0
  choices[0] = 0
  transitions = 0 ## i64
  i = 1
  while i < half
    transitions += ffcd_state(i,gains,dp,choices)
    i += 1
  full = size - 1 ## i64
  transitions += ffcd_state(full,gains,dp,choices)
  remaining = full ## i64
  selected = 0 ## i64
  body = ""
  sum = 0 ## i64
  while remaining > 0
    edge = choices[remaining] ## i64
    if edge > 0
      body = body + edge.to_s() + " " + gains[edge].to_s() + "\n"
      sum += gains[edge]
      selected += 1
      remaining = remaining ^ edge
    else
      bit = 1 ## i64
      while (bit << 1) <= remaining
        bit = bit << 1
      remaining = remaining ^ bit
  if sum != dp[full]
    << "internal reconstruction mismatch"
    exit(1)
  << "PACK_JOB index=" + job.to_s() + " gain=" + dp[full].to_s() + " states=" + half.to_s() + " transitions=" + transitions.to_s() + " selected=" + selected.to_s()
  if selected > 0
    print(body)
  job += 1
if line != lines.size()
  << "trailing component input"
  exit(2)
