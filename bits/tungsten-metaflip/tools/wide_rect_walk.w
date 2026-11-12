# Standalone finite multiword rectangular walk. MFW1 input/output are fully
# checked before admission; this does not mutate the fleet's live archives.
#
#   wide-rect-walk NxMxP SEED.mfw OUTPUT.mfw STEPS [NONCE] [options]
#
# Without options this is the campaign walk. Options, each defaulting to the
# campaign behaviour:
#   --target R              stop as soon as the best rank is <= R
#   --trace                 print a TRACE line at every new best rank
#   --json                  print a one-line JSON summary after the result line
#   --cpu-budget SECONDS    stop once this process has used that much CPU time
#                           (STEPS may then be `unlimited`)
#   --proposal directed|uniform
#                           legal-bucket proposals, or uniform term/position/partner
#   --guard nonbacktracking|none|tabu     (tabu table size: --history N, default 4096)
#   --split-period P        split every P proposals, 0: never (default 2000)
#   --split-stall R         split and forget the history after R consecutive
#                           rejections, 0: never (default 256)
#   --split-no-pair on|off  split when no legal pair exists (default on)
#   --slack K               split only while rank < best + K (default 8)
#   --restart X             restart from the seed every X proposals, 0: never
use ../lib/metaflip/wide/directed
use core/file
use core/crypto/sha256

FLAGS = ["--trace", "--json"]
VALUED = ["--target", "--cpu-budget", "--proposal", "--guard", "--history", "--split-period", "--split-stall", "--split-no-pair", "--slack", "--restart"]

# CPU time of this process (user + system) in microseconds.
-> cpu_us() i64
  ccall_nobox("clock")

# Decimal digits, leading zeros allowed; -1 when malformed.
-> digits_value(text) (String) i64
  if text.size < 1 || text.size > 12
    return 0-1
  out = 0 ## i64
  i = 0 ## i64
  while i < text.size
    d = text.byte_at(i)-48 ## i64
    if d < 0 || d > 9
      return 0-1
    out = out*10+d
    i += 1
  out

# "12.345" -> 12345000 (microseconds); -1 when malformed.
-> seconds_us(text) (String) i64
  parts = text.split(".")
  if parts.size < 1 || parts.size > 2
    return 0-1
  whole = digits_value(parts[0]) ## i64
  frac = 0 ## i64
  if parts.size == 2
    if parts[1].size > 6
      return 0-1
    frac = digits_value(parts[1]+"000000".slice(0, 6-parts[1].size))
  if whole < 0 || frac < 0
    return 0-1
  whole*1000000+frac

# Microseconds as milliseconds with three decimals.
-> ms_text(us) (i64)
  frac = (us % 1000).to_s
  while frac.size < 3
    frac = "0" + frac
  (us / 1000).to_s + "." + frac

# Splits the arguments into positionals and an option table; nil on a malformed option.
-> parse_args(args)
  positional = []
  opts = {}
  i = 0 ## i64
  while i < args.size
    arg = args[i]
    if arg.starts_with?("--")
      if FLAGS.include?(arg)
        opts[arg] = "1"
      elsif VALUED.include?(arg) && i+1 < args.size
        opts[arg] = args[i+1]
        i += 1
      else
        return nil
    else
      positional.push(arg)
    i += 1
  [positional, opts]

# Value of a numeric option, `fallback` when absent, -1 when malformed.
-> option_number(opts, name, fallback) (Hash String i64) i64
  text = opts[name]
  if text == nil
    return fallback
  digits_value(text)

# Value of an on/off option, `fallback` when absent, -1 when malformed.
-> option_switch(opts, name, fallback) (Hash String i64) i64
  text = opts[name]
  if text == nil
    return fallback
  if text == "on"
    return 1
  if text == "off"
    return 0
  0-1

# One walk from a seed scheme: state, switches and running totals. Restarts
# rebuild the state from the seed and keep the random stream running.
+ Walk
  rw :stopped
  ro :kept, :proposals, :flips, :no_pair, :escapes, :restarts, :kept_rank, :seen, :best_proposals, :best_flips, :best_cpu_us

  -> new(@seed, @rank, @dims, @cap, @nonce, @settings)
    st_words = ffws_words_rect(@dims[0], @dims[1], @dims[2], @cap) ## i64
    @st = i64[st_words]
    @control = nil
    scratch_words = 12*ffpk_stride(@dims[0], @dims[1], @dims[2]) ## i64
    @scratch = i64[scratch_words]
    @stop = i64[1]
    @kept = i64[@seed.size]
    @proposals = 0
    @flips = 0
    @no_pair = 0
    @escapes = 0
    @restarts = 0
    @kept_rank = 0
    @kept_bits = 0
    @seen = @rank
    @best_proposals = 0
    @best_flips = 0
    @best_cpu_us = 0
    @stopped = nil

  # Builds the state, control and switches; false when the seed or a switch is rejected.
  -> start(rng)
    if ffws_init_rect(@st, @dims[0], @dims[1], @dims[2], @cap, @seed, @rank, @nonce) != 1
      return false
    if rng != nil
      @st[6] = rng
    if @control == nil
      control_words = ffwd_words(@st, @settings["history"]) ## i64
      @control = i64[control_words]
    if ffwd_init(@st, @control, @settings["mode"], @settings["history"]) != 1
      return false
    s = @settings
    if s["custom"] == 1 && ffwd_policy(@control, s["period"], s["stall"], s["no_pair"], s["slack"], s["proposal"]) != 1
      return false
    if s["events"] == 1
      ffwd_watch(@control, s["target"], @seen)
    true

  # Executes up to `steps` proposals of the current state; false when the walk fails.
  -> segment(steps)
    base = @st[7] ## i64
    done = 0 ## i64
    while done < steps && @stopped == nil
      batch = steps-done ## i64
      if batch > @settings["batch"]
        batch = @settings["batch"]
      if ffwd_work(@st, @scratch, @control, batch, @stop, 8) < 0
        return false
      done = @st[7]-base
      if @st[5] < @seen
        self.record_best
      if @settings["target"] > 0 && @st[5] <= @settings["target"]
        @stopped = "target"
      elsif @settings["budget_us"] > 0 && cpu_us() >= @settings["budget_us"]
        @stopped = "budget"
    true

  -> record_best
    @seen = @st[5]
    @best_proposals = @proposals + @st[7]
    @best_flips = @flips + @st[8]
    @best_cpu_us = cpu_us()
    if @settings["trace"] == 1
      << "TRACE rank=" + @seen.to_s + " proposals=" + @best_proposals.to_s + " flips=" + @best_flips.to_s + " cpu_ms=" + ms_text(@best_cpu_us)
      ccall("w_flush")
    if @settings["events"] == 1
      ffwd_watch(@control, @settings["target"], @seen)

  # Folds the finished segment into the totals and keeps its best scheme if better.
  -> close_segment
    @proposals += @st[7]
    @flips += @st[8]
    @no_pair += @st[23]
    @escapes += @control[17]
    if @kept_rank == 0 || @st[5] < @kept_rank || (@st[5] == @kept_rank && @st[11] < @kept_bits)
      ffws_export(@st, @kept, 1)
      @kept_rank = @st[5]
      @kept_bits = @st[11]

  # The whole walk after `start`: `steps` proposals split into restart segments.
  -> run(steps)
    executed = 0 ## i64
    while executed < steps && @stopped == nil
      length = steps-executed ## i64
      if @settings["restart"] > 0 && length > @settings["restart"]
        length = @settings["restart"]
      if !self.segment(length)
        return false
      executed += @st[7]
      self.close_segment
      if executed < steps && @stopped == nil
        @restarts += 1
        rng = @st[6]
        if !self.start(rng)
          return false
    if @stopped == nil
      @stopped = "steps"
    true

-> usage()
  << "usage: wide-rect-walk NxMxP SEED.mfw OUTPUT.mfw STEPS [NONCE] [options]"
  << "options: --target R --trace --json --cpu-budget SECONDS --proposal directed|uniform"
  << "  --guard nonbacktracking|none|tabu --history N --split-period P --split-stall R"
  << "  --split-no-pair on|off --slack K --restart X"
  exit(2)

args = argv()
parsed = parse_args(args)
if parsed == nil || parsed[0].size != 4 && parsed[0].size != 5
  usage()
positional = parsed[0]
opts = parsed[1]
shape = positional[0].split("x")
if shape.size != 3
  << "invalid tensor shape"
  exit(2)
n = ffpk_decimal(shape[0]) ## i64
m = ffpk_decimal(shape[1]) ## i64
p = ffpk_decimal(shape[2]) ## i64
stride = ffpk_stride(n,m,p) ## i64
budget_us = 0 ## i64
if opts["--cpu-budget"] != nil
  budget_us = seconds_us(opts["--cpu-budget"])
  if budget_us < 1
    << "invalid CPU budget"
    exit(2)
steps = ffpk_decimal(positional[3]) ## i64
if positional[3] == "unlimited" && budget_us > 0
  steps = 1 << 60
nonce = 19071 ## i64
if positional.size == 5
  nonce = ffpk_decimal(positional[4])
if n < 2 || m < 2 || p < 2 || stride < 1 || steps < 1 || steps > 1000000000 && budget_us == 0 || nonce < 1 || nonce > 2147483647 || File.exists?(positional[2])
  << "invalid dimensions, step count, or existing output"
  exit(2)
guards = {"none" => 1, "nonbacktracking" => 2, "tabu" => 3}
guard_name = opts["--guard"]
if guard_name == nil
  guard_name = "nonbacktracking"
proposal_name = opts["--proposal"]
if proposal_name == nil
  proposal_name = "directed"
target = option_number(opts, "--target", 0) ## i64
history = option_number(opts, "--history", 4096) ## i64
period = option_number(opts, "--split-period", 2000) ## i64
stall = option_number(opts, "--split-stall", 256) ## i64
no_pair = option_switch(opts, "--split-no-pair", 1) ## i64
slack = option_number(opts, "--slack", 8) ## i64
restart = option_number(opts, "--restart", 0) ## i64
if guards[guard_name] == nil || (proposal_name != "directed" && proposal_name != "uniform") || target < 0 || history < 2 || period < 0 || stall < 0 || no_pair < 0 || slack < 0 || restart < 0
  << "invalid option value"
  exit(2)
raw = read_file(positional[1])
if raw == nil
  << "missing seed"
  exit(2)
# Match the MFW1 reader's rank limit; the live fleet keeps its smaller cap.
data = i64[3*stride*16384]
meta = i64[4]
rank = ffpk_parse(raw,data,data.size(),meta,4) ## i64
if rank < 1 || meta[0] != n || meta[1] != m || meta[2] != p || rank+64 > 16384
  << "invalid MFW1 seed"
  exit(2)
parity = i64[m*p*((n*p+31)/32)]
if ffpk_exact(data,data.size(),rank,n,m,p,parity,parity.size(),0) != 1
  << "seed failed full tensor verification"
  exit(2)
trace = 0 ## i64
if opts["--trace"] != nil
  trace = 1
json = 0 ## i64
if opts["--json"] != nil
  json = 1
proposal = 0 ## i64
if proposal_name == "uniform"
  proposal = 1
# Only a non-default switch or a watch reaches the walker; the campaign call path stays untouched.
custom = 0 ## i64
if proposal != 0 || period != 2000 || stall != 256 || no_pair != 1 || slack != 8
  custom = 1
events = 0 ## i64
if trace == 1 || json == 1 || target > 0 || restart > 0
  events = 1
batch = 100000 ## i64
if budget_us > 0
  batch = 4096
settings = {"mode" => guards[guard_name], "history" => history, "period" => period, "stall" => stall, "no_pair" => no_pair, "slack" => slack, "proposal" => proposal, "custom" => custom, "events" => events, "target" => target, "trace" => trace, "budget_us" => budget_us, "batch" => batch, "restart" => restart}
cap = rank+64 ## i64
walk = Walk.new(data, rank, [n, m, p], cap, nonce, settings)
if !walk.start(nil)
  << "wide rectangular initialization failed"
  exit(2)
if !walk.run(steps)
  << "directed walk failed"
  exit(1)
best_data = walk.kept
best = walk.kept_rank ## i64
if best < 1 || ffpk_exact(best_data,best_data.size(),best,n,m,p,parity,parity.size(),0) != 1
  << "result failed full tensor verification"
  exit(1)
if ffpk_canonicalize(best_data,best_data.size(),best,stride) != best
  << "result canonicalization failed"
  exit(1)
blob = ffpk_blob(best_data,best,n,m,p)
if !write_file(positional[2],blob)
  << "cannot write result"
  exit(1)
<< "WIDE_RECT_RESULT tensor="+positional[0]+" seed_rank="+rank.to_s+" rank="+best.to_s+" moves="+walk.proposals.to_s+" accepted="+walk.flips.to_s+" no_pair="+walk.no_pair.to_s+" escapes="+walk.escapes.to_s+" nonce="+nonce.to_s+" output="+positional[2]
if json == 1
  hit = "false"
  target_text = "null"
  if target > 0
    target_text = target.to_s
    if best <= target
      hit = "true"
  no_pair_text = "false"
  if no_pair == 1
    no_pair_text = "true"
  << "{\"tool\":\"wide_rect_walk\",\"schema\":1,\"shape\":\"" + positional[0] + "\",\"seed_rank\":" + rank.to_s + ",\"rank\":" + best.to_s + ",\"target\":" + target_text + ",\"hit\":" + hit + ",\"proposals\":" + walk.proposals.to_s + ",\"flips\":" + walk.flips.to_s + ",\"proposals_to_best\":" + walk.best_proposals.to_s + ",\"flips_to_best\":" + walk.best_flips.to_s + ",\"cpu_ms\":" + ms_text(cpu_us()) + ",\"cpu_ms_to_best\":" + ms_text(walk.best_cpu_us) + ",\"nonce\":" + nonce.to_s + ",\"stopped\":\"" + walk.stopped + "\",\"sha256\":\"" + Crypto:SHA256.hexdigest(blob) + "\",\"proposal\":\"" + proposal_name + "\",\"guard\":\"" + guard_name + "\",\"history\":" + history.to_s + ",\"split_period\":" + period.to_s + ",\"split_stall\":" + stall.to_s + ",\"split_no_pair\":" + no_pair_text + ",\"slack\":" + slack.to_s + ",\"restart\":" + restart.to_s + ",\"restarts\":" + walk.restarts.to_s + "}"
