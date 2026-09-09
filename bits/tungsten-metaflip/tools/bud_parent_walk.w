use bud_holdout
use bud_mixed_score

# Bounded one-thread experiment; never touches a fleet archive or a GPU.
if ARGV.size() < 10 || ARGV.size() > 14
  << "usage: bud_parent_walk SEED SHAPE PRICES TRIALS CHUNKS STEPS MODE RNG OUTDIR DEBT; optional DENSITY_SLACK, OBSERVE_EVERY, HOLDOUT_FILE, VERIFIED_HOLDOUT_COST"
  exit(2)
source = ARGV[0]
shape = ARGV[1]
table_path = ARGV[2]
trials = ARGV[3].to_i() ## i64
chunks = ARGV[4].to_i() ## i64
steps = ARGV[5].to_i() ## i64
mode = ARGV[6]
seed = ARGV[7].to_i() ## i64
outdir = ARGV[8]
debt = ARGV[9].to_i() ## i64
density_slack = 4 ## i64
if ARGV.size() >= 11
  density_slack = ARGV[10].to_i()
observe_every = steps ## i64
if ARGV.size() >= 12
  observe_every = ARGV[11].to_i()
n = ffrp_label_axis(shape,0) ## i64
m = ffrp_label_axis(shape,1) ## i64
p = ffrp_label_axis(shape,2) ## i64
if shape != n.to_s() + "x" + m.to_s() + "x" + p.to_s() || ffbp_supported(n,m,p) != 1 || trials < 1 || trials > 4096 || chunks < 1 || chunks > 100000 || steps < 1 || steps > 1000000 || debt < 0 || debt > 8 || density_slack < 0 || density_slack > 1024 || observe_every < 1 || observe_every > steps
  << "invalid shape or search budget"
  exit(2)
if mode != "walk" && mode != "greedy" && mode != "anneal"
  << "invalid strategy"
  exit(2)
if !File.mkdir_p(outdir)
  << "cannot create parent output directory"
  exit(2)
table = read_file(table_path)
if table == nil
  << "missing price table"
  exit(2)
lines = table.strip().split("\n")
observer_count = 0 ## i64
mixed_count = 0 ## i64
mixed_budget = 0 ## i64
if lines.size() != 4 && lines.size() != 5
  if lines.size() < 6
    << "invalid price rows"
    exit(2)
  header = lines[4].split(" ")
  if header.size() == 3 && header[0] == "mixed-observers"
    mixed_count = header[1].to_i()
    mixed_budget = header[2].to_i()
    mixed_count_label = mixed_count.to_s()
    mixed_budget_label = mixed_budget.to_s()
    if mixed_count < 1 || mixed_count > 8 || mixed_count_label != header[1] || mixed_budget < 1 || mixed_budget > 1000000 || mixed_budget_label != header[2] || lines.size() != 5+mixed_count || mode != "walk" || ARGV.size() >= 13
      << "invalid mixed observer layout or strategy"
      exit(2)
    observer_count = mixed_count
  elsif header.size() == 2 && header[0] == "observers"
    observer_count = header[1].to_i()
    observer_label = observer_count.to_s()
    # Sidecars do not steer the walk. Holdout/grid objectives require a
    # different cover and are deliberately not supported by these tables.
    if observer_count < 1 || observer_count > 8 || observer_label != header[1] || lines.size() != 5 + 3 * observer_count || mode != "walk" || ARGV.size() >= 13
      << "invalid observer layout or strategy"
      exit(2)
  else
    << "invalid observer header"
    exit(2)
limit = lines[0].to_i() ## i64
if limit < 1 || limit > 4096 || (mixed_count > 0 && limit > 512)
  << "invalid price rank limit"
  exit(2)
stride = limit + 1 ## i64
prices = i64[3 * stride]
axis = 0 ## i64
while axis < 3
  fields = lines[axis + 1].split(" ")
  if fields.size() != stride
    << "invalid price columns"
    exit(2)
  i = 0 ## i64
  while i < stride
    price = fields[i].to_i() ## i64
    if price < 0 || price > 1000000000 || (i == 0 && price != 0) || (i > 0 && price == 0)
      << "invalid bucket price"
      exit(2)
    prices[axis * stride + i] = price
    i += 1
  axis += 1
# Observer mode uses the same whole-tensor cover as the primary objective.
# Put the primary table first so all objectives share one grouping pass.
scored_tables = 0 ## i64
if observer_count > 0
  scored_tables = observer_count + 1
observer_prices = i64[3 * stride * scored_tables]
if observer_count > 0 && mixed_count == 0
  i = 0 ## i64
  while i < 3 * stride
    observer_prices[i] = prices[i]
    i += 1
observer = 0 ## i64
while observer < observer_count && mixed_count == 0
  axis = 0
  while axis < 3
    fields = lines[5 + 3 * observer + axis].split(" ")
    if fields.size() != stride
      << "invalid observer price columns"
      exit(2)
    i = 0 ## i64
    while i < stride
      price = fields[i].to_i() ## i64
      price_label = price.to_s()
      if price < 0 || price > 1000000000 || price_label != fields[i] || (i == 0 && price != 0) || (i > 0 && price == 0)
        << "invalid observer bucket price"
        exit(2)
      observer_prices[(3 * (observer + 1) + axis) * stride + i] = price
      i += 1
    axis += 1
  observer += 1
mixed_tables = i64[4*mixed_count]
observer = 0
while observer < mixed_count
  fields = lines[5+observer].split(" ")
  if fields.size() != 4
    << "invalid mixed observer prices"
    exit(2)
  i = 0 ## i64
  while i < 4
    price = fields[i].to_i() ## i64
    price_label = price.to_s()
    if price < 1 || price > 128 || price_label != fields[i]
      << "invalid mixed observer prices"
      exit(2)
    mixed_tables[4*observer+i] = price
    i += 1
  observer += 1
mixed_scratch = 0 ## i64
if mixed_count > 0
  mixed_scratch = 1
mixed_parent = i64[3*512*mixed_scratch]
mixed_costs = i64[4*mixed_scratch]
mixed_mates = i64[512*mixed_scratch]
mixed_axes = i64[512*mixed_scratch]
mixed_work = i64[6*512*mixed_scratch]
mixed_memo = i64[65536*mixed_scratch]
mixed_choice = i64[65536*mixed_scratch]
mixed_status = i64[3*mixed_scratch]
mixed_totals = i64[4]
grid_prices = i64[3]
if lines.size() == 5
  fields = lines[4].split(" ")
  if fields.size() != 4 || fields[0] != "grids" || limit > 64
    << "invalid grid prices or rank limit"
    exit(2)
  axis = 0
  while axis < 3
    price = fields[axis + 1].to_i() ## i64
    if price < 1 || price > 1000000000
      << "invalid grid prices or rank limit"
      exit(2)
    grid_prices[axis] = price
    axis += 1
capacity = ffr_default_capacity(n,m,p) ## i64
words = ffr_state_size(capacity) ## i64
original = i64[words]
anchor = i64[words]
work = i64[words]
winner = i64[words]
observed = i64[words]
observer_winners = i64[words * observer_count]
observer_scores = i64[observer_count]
observer_current_scores = i64[scored_tables]
observer_ranks = i64[observer_count]
observer_bits = i64[observer_count]
observer_at = i64[observer_count]
observer_scratch_words = 0 ## i64
if observer_count > 0
  observer_scratch_words = words
observer_scratch = i64[observer_scratch_words]
held = i64[3 * capacity]
keys = i64[capacity]
counts = i64[capacity]
rank = ffbp_load(original,source,n,m,p,capacity,seed,density_slack) ## i64
if rank < 1 || limit < rank + debt || ffbp_verify(original,n,m,p) != 1
  << "invalid seed or insufficient price table"
  exit(2)
original[10] = debt
original[40] = debt
held_count = 0 ## i64
held_cost = 0 ## i64
if ARGV.size() >= 13
  held_text = read_file(ARGV[12])
  if held_text == nil
    << "missing holdout file"
    exit(2)
  held_lines = held_text.strip().split("\n")
  held_count = held_lines[0].to_i()
  if held_count < 1 || held_count >= rank || held_lines.size() != held_count + 1
    << "invalid holdout count"
    exit(2)
  i = 0 ## i64
  while i < held_count
    fields = held_lines[i+1].split(" ")
    if fields.size() != 3
      << "invalid holdout term"
      exit(2)
    axis = 0
    while axis < 3
      held[3*i+axis] = fields[axis].to_i()
      if held[3*i+axis] < 1 || held[3*i+axis].to_s() != fields[axis]
        << "invalid holdout mask"
        exit(2)
      axis += 1
    i += 1
  z = ffbp_copy(original,observed,words)
  if ffbh_remove(observed,held,held_count) != 1
    << "holdout terms must be distinct literal seed terms"
    exit(2)
  << "BUD_HOLDOUT count=" + held_count.to_s()
if ARGV.size() == 14
  held_cost = ARGV[13].to_i()
  if held_cost < 1 || held_cost > 1000000000 || held_cost.to_s() != ARGV[13] || grid_prices[0] != 0
    << "invalid verified holdout cost"
    exit(2)
# observed is the private residual copy established above. A zero held_cost
# preserves the previous objective and never reads that residual argument.
initial = ffbh_cost(original,observed,0,held_cost,prices,stride,keys,counts,grid_prices) ## i64
attempted = 0 ## i64
flips_accepted = 0 ## i64
restarts_accepted = 0 ## i64
sampled_peak_rank = rank ## i64
sampled_peak_bits = ffr_current_bits(original) ## i64
observations = 0 ## i64
holdout_cancellations = 0 ## i64
start_ms = ccall("__w_clock_ms") ## i64
trial = 0 ## i64
while trial < trials
  z = ffbp_copy(original,anchor,words)
  if held_count > 0 && ffbh_remove(anchor,held,held_count) != 1
    << "holdout initialization failed"
    exit(1)
  z = ffbp_copy(original,winner,words)
  anchor_score = initial ## i64
  best = initial ## i64
  best_rank = rank ## i64
  best_bits = ffr_current_bits(original) ## i64
  best_at = 0 ## i64
  accepted = 0 ## i64
  if mixed_count > 0
    if ffbp_mixed_costs(original,mixed_tables,mixed_count,observer_current_scores,mixed_parent,mixed_costs,mixed_mates,mixed_axes,mixed_work,mixed_memo,mixed_choice,mixed_status,mixed_totals,mixed_budget) != 1
      << "invalid initial mixed observer score"
      exit(1)
  elsif observer_count > 0
    z = ffbp_observer_costs(original,observer_prices,stride,scored_tables,keys,counts,observer_current_scores)
  observer = 0
  while observer < observer_count
    z = ffbp_store_observer(original,observer_winners,observer * words,words)
    observer_scores[observer] = observer_current_scores[observer + 1]
    observer_ranks[observer] = rank
    observer_bits[observer] = ffr_current_bits(original)
    observer_at[observer] = 0
    observer += 1
  chunk = 0 ## i64
  while chunk < chunks
    z = ffbp_copy(anchor,work,words)
    # Rejected proposals cannot roll back the external attempt clock/RNG salt.
    work[13] = chunk * steps
    z = ffw_seed_rng(work,seed + trial * 104729 + chunk * 8191)
    done = 0 ## i64
    score = anchor_score ## i64
    while done < steps
      span = observe_every ## i64
      if span > steps - done
        span = steps - done
      before = work[21] ## i64
      z = ffbp_wander(work,span,n,m,p)
      flips_accepted += work[21] - before
      attempted += span
      done += span
      observations += 1
      # Every score describes a cover of the joined full tensor. The residual
      # state has a different target and is never admitted or exported alone.
      cancelled = ffbh_join(work,observed,words,held,held_count) ## i64
      if cancelled < 0
        << "holdout join capacity failed"
        exit(1)
      holdout_cancellations += cancelled
      if mixed_count > 0
        score = ffbh_cost(observed,work,cancelled,held_cost,prices,stride,keys,counts,grid_prices)
        if ffbp_mixed_costs(observed,mixed_tables,mixed_count,observer_current_scores,mixed_parent,mixed_costs,mixed_mates,mixed_axes,mixed_work,mixed_memo,mixed_choice,mixed_status,mixed_totals,mixed_budget) != 1
          << "invalid mixed observer score"
          exit(1)
      elsif observer_count > 0
        z = ffbp_observer_costs(observed,observer_prices,stride,scored_tables,keys,counts,observer_current_scores)
        score = observer_current_scores[0]
      else
        score = ffbh_cost(observed,work,cancelled,held_cost,prices,stride,keys,counts,grid_prices)
      current_rank = ffr_current_rank(observed) ## i64
      bits = ffr_current_bits(observed) ## i64
      if current_rank > sampled_peak_rank
        sampled_peak_rank = current_rank
      if bits > sampled_peak_bits
        sampled_peak_bits = bits
      if ffbp_better(score,current_rank,bits,best,best_rank,best_bits) == 1
        # The observer must not mutate the walked state, even through verifier
        # counters. Copy first so walk/greedy trajectories are cadence-neutral.
        z = ffbp_copy(observed,winner,words)
        if ffbp_verify(winner,n,m,p) != 1
          << "inexact proposed parent"
          exit(1)
        best = score
        best_rank = current_rank
        best_bits = bits
        best_at = chunk * steps + done
      observer = 0
      while observer < observer_count
        observer_score = observer_current_scores[observer + 1] ## i64
        if ffbp_better(observer_score,current_rank,bits,observer_scores[observer],observer_ranks[observer],observer_bits[observer]) == 1
          z = ffbp_copy(observed,observer_scratch,words)
          if ffbp_verify(observer_scratch,n,m,p) != 1
            << "inexact observer parent"
            exit(1)
          z = ffbp_store_observer(observer_scratch,observer_winners,observer * words,words)
          observer_scores[observer] = observer_score
          observer_ranks[observer] = current_rank
          observer_bits[observer] = bits
          observer_at[observer] = chunk * steps + done
        observer += 1
    if ffbp_accept(mode,score,anchor_score,best,chunk) == 1
      z = ffbp_copy(work,anchor,words)
      anchor_score = score
      accepted += 1
      restarts_accepted += 1
    chunk += 1
  path = outdir + "/trial-" + trial.to_s() + ".txt"
  if read_file(path) != nil
    << "refusing to overwrite parent output"
    exit(2)
  saved = ffbp_dump(winner,path,n,m,p) ## i64
  if saved != best_rank
    << "parent output gate failed"
    exit(1)
  if ARGV.size() >= 12
    end_path = outdir + "/end-" + trial.to_s() + ".txt"
    if ffbh_join(anchor,observed,words,held,held_count) < 0
      << "end-state holdout join failed"
      exit(1)
    if read_file(end_path) != nil || ffbp_dump(observed,end_path,n,m,p) != ffr_current_rank(observed)
      << "end-state output gate failed"
      exit(1)
  observer = 0
  while observer < observer_count
    prefix = "observer-"
    label = "BUD_OBSERVER"
    if mixed_count > 0
      prefix = "mixed-observer-"
      label = "BUD_MIXED_OBSERVER"
    observer_path = outdir + "/" + prefix + observer.to_s() + "-trial-" + trial.to_s() + ".txt"
    if read_file(observer_path) != nil
      << "refusing to overwrite observer output"
      exit(2)
    z = ffbp_load_observer(observer_winners,observer * words,observer_scratch,words)
    if ffbp_dump(observer_scratch,observer_path,n,m,p) != observer_ranks[observer]
      << "observer output gate failed"
      exit(1)
    << label + " observer=" + observer.to_s() + " trial=" + trial.to_s() + " score=" + observer_scores[observer].to_s() + " rank=" + observer_ranks[observer].to_s() + " bits=" + observer_bits[observer].to_s() + " best_at=" + observer_at[observer].to_s()
    observer += 1
  << "BUD_TRIAL trial=" + trial.to_s() + " strategy=" + mode + " score=" + best.to_s() + " rank=" + best_rank.to_s() + " bits=" + best_bits.to_s() + " chunks_accepted=" + accepted.to_s() + " best_at=" + best_at.to_s()
  trial += 1
elapsed = ccall("__w_clock_ms") - start_ms ## i64
if mixed_count > 0
  << "BUD_MIXED observers=" + mixed_count.to_s() + " budget=" + mixed_budget.to_s() + " evaluations=" + mixed_totals[0].to_s() + " states=" + mixed_totals[1].to_s() + " fallback_components=" + mixed_totals[2].to_s() + " components=" + mixed_totals[3].to_s()
<< "BUD_RESULT strategy=" + mode + " trials=" + trials.to_s() + " chunks=" + chunks.to_s() + " steps=" + steps.to_s() + " attempted=" + attempted.to_s() + " accepted_flips=" + flips_accepted.to_s() + " accepted_chunks=" + restarts_accepted.to_s() + " initial=" + initial.to_s() + " density_slack=" + density_slack.to_s() + " observe_every=" + observe_every.to_s() + " observations=" + observations.to_s() + " sampled_peak_rank=" + sampled_peak_rank.to_s() + " sampled_peak_bits=" + sampled_peak_bits.to_s() + " held_terms=" + held_count.to_s() + " held_cost=" + held_cost.to_s() + " holdout_cancellations=" + holdout_cancellations.to_s() + " elapsed_ms=" + elapsed.to_s()
