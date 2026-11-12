# The runs of one algorithm on one task, and the statistics computed from them
# (bench/README.md, section 7). Times are in one unit throughout (the fixture
# uses milliseconds, the records use seconds); costs are non-negative.
use stats

# The runs of one algorithm on one task. A run has a hit flag, the CPU it spent
# (the time to the target for a hit), optional counts of retired instructions,
# proposals and flips, and a trace of `(time, rank)` improvements. Times are
# measured in units of 1/`per_second` seconds.
+ Sample
  ro :budget, :start_rank, :target_rank

  -> new(@budget, @start_rank, @target_rank, @per_second)
    @hits = []
    @spent = []
    @counts = {"instr" => [], "proposals" => [], "flips" => []}
    @trace_times = []
    @trace_ranks = []

  # Adds a run; counts are nil where the tool did not report them, the trace
  # is a pair of arrays (times, ranks) or nil.
  -> add(hit, spent, instr, proposals, flips, times, ranks)
    @hits.push(hit ? 1 : 0)
    @spent.push(spent.to_f)
    @counts["instr"].push(instr)
    @counts["proposals"].push(proposals)
    @counts["flips"].push(flips)
    @trace_times.push(times)
    @trace_ranks.push(ranks)

  -> size
    @hits.size

  -> hit_count
    @hits.sum

  # The hit flags as a typed array of 1.0 and 0.0.
  -> hit_flags
    out = f64[@hits.size]
    i = 0 ## i64
    while i < @hits.size
      out[i] = @hits[i].to_f
      i += 1
    out

  # Cost of each run on an axis: `cpu` (the time to target for a hit, the budget
  # for a censored run) or a reported count. nil when some run lacks the count.
  -> costs(axis)
    out = f64[@hits.size]
    budget = @budget.to_f ## f64
    i = 0 ## i64
    while i < @hits.size
      if axis == "cpu"
        out[i] = @hits[i] == 1 ? @spent[i].to_f : budget
      else
        value = @counts[axis][i]
        return nil if value == nil
        out[i] = value.to_f
      i += 1
    out

  # Expected running time with restarts on an axis: infinite without a hit, nil when the axis is not recorded.
  -> ert(axis)
    values = self.costs(axis)
    return nil if values == nil || @hits.size == 0
    Stats.ert(values, self.hit_flags)

  # Bootstrap interval of the ERT on an axis (nil when the axis is not recorded).
  -> ert_interval(axis, seed, reps)
    values = self.costs(axis)
    return nil if values == nil || @hits.size == 0
    Stats.ert_interval(values, self.hit_flags, seed, reps)

  -> wilson
    Stats.wilson(self.hit_count, @hits.size)

  # Kaplan-Meier estimate of the time to target.
  -> survival
    Stats.kaplan_meier(self.costs("cpu"), self.hit_flags)

  # Counts per CPU time over the runs that reported the count; nil when none did.
  -> throughput(axis)
    total = 0.0 ## f64
    time = 0.0 ## f64
    per_second = @per_second.to_f ## f64
    seen = 0 ## i64
    i = 0 ## i64
    while i < @hits.size
      value = @counts[axis][i]
      if value != nil
        total = total + value.to_f
        time = time + @spent[i].to_f
        seen += 1
      i += 1
    return nil if seen == 0
    total / time * per_second

  # Rank of run i at time t: the rank of its last trace entry not after t, else the start rank.
  -> rank_at(i, at)
    t = at.to_f ## f64
    rank = @start_rank.to_f ## f64
    times = @trace_times[i]
    ranks = @trace_ranks[i]
    if times == nil
      return rank
    k = 0 ## i64
    while k < times.size && times[k] <= t
      rank = ranks[k]
      k += 1
    rank

  # The ranks of all runs at time t, ascending.
  -> ranks_at(at)
    t = at.to_f ## f64
    out = f64[@hits.size]
    i = 0 ## i64
    while i < @hits.size
      out[i] = self.rank_at(i, t)
      i += 1
    out.sort

  # Area under the normalised rank of one run over [budget/1000, budget] in log time, divided by ln 1000.
  -> run_auc(i)
    times = @trace_times[i]
    ranks = @trace_ranks[i]
    budget = @budget.to_f ## f64
    goal = @target_rank.to_f ## f64
    span = (@start_rank - @target_rank).to_f ## f64
    lo = budget / 1000.0 ## f64
    level = @start_rank.to_f ## f64
    k = 0 ## i64
    if times != nil
      while k < times.size && times[k] <= lo
        level = ranks[k]
        k += 1
    area = 0.0 ## f64
    cursor = Math.log(lo) ## f64
    if times != nil
      while k < times.size && times[k] < budget
        here = Math.log(times[k]) ## f64
        area = area + (level - goal) / span * (here - cursor)
        level = ranks[k]
        cursor = here
        k += 1
    area = area + (level - goal) / span * (Math.log(budget) - cursor)
    area / Math.log(1000.0)

  # Mean AUC over the runs; lower is better.
  -> auc
    total = 0.0 ## f64
    i = 0 ## i64
    while i < @hits.size
      total = total + self.run_auc(i)
      i += 1
    total / @hits.size.to_f

  # Quartiles of the run ranks at the `points` log-spaced times of the last
  # `decades` decades before the budget: rows [time, q25, q50, q75].
  -> descent(points, decades) (i64 i64)
    rows = []
    budget = @budget.to_f ## f64
    g = 0 ## i64
    while g < points
      e = 0.0 - decades.to_f + g.to_f * decades.to_f / (points - 1).to_f ## f64
      t = budget * Math.pow(10.0, e) ## f64
      ranks = self.ranks_at(t)
      rows.push([t, Stats.quantile(ranks, 0.25), Stats.quantile(ranks, 0.5), Stats.quantile(ranks, 0.75)])
      g += 1
    rows

# Two samples compared on the CPU axis with independently resampled arms.
+ Comparison
  ro :ratio, :ratio_interval, :kept, :difference, :difference_interval

  -> new(@ratio, @ratio_interval, @kept, @difference, @difference_interval)

  # A against the reference B: the ERT ratio and the success-rate difference
  # with 95% bootstrap intervals; `reps` resamples of both arms.
  -> .of(a, b, seed, reps)
    costs_a = a.costs("cpu")
    hits_a = a.hit_flags
    costs_b = b.costs("cpu")
    hits_b = b.hit_flags
    cell = Stats.generator(seed)
    ratios = f64[reps]
    diffs = f64[reps]
    size_a = a.size.to_f ## f64
    size_b = b.size.to_f ## f64
    inf = Stats.inf() ## f64
    kept = 0 ## i64
    r = 0 ## i64
    while r < reps
      da = Stats.resample(costs_a, hits_a, cell)
      db = Stats.resample(costs_b, hits_b, cell)
      cost_a = da[0] ## f64
      wins_a = da[1] ## f64
      cost_b = db[0] ## f64
      wins_b = db[1] ## f64
      diffs[r] = wins_a / size_a - wins_b / size_b
      ea = Stats.ratio(cost_a, wins_a) ## f64
      eb = Stats.ratio(cost_b, wins_b) ## f64
      if ea != inf || eb != inf
        value = 0.0 ## f64
        if ea == inf
          value = inf
        elsif eb != inf
          value = ea / eb
        ratios[kept] = value
        kept += 1
      r += 1
    point = nil
    ert_a = a.ert("cpu")
    ert_b = b.ert("cpu")
    if ert_a != nil && ert_b != nil && ert_a != Stats.inf() && ert_b != Stats.inf()
      point = ert_a / ert_b
    interval = nil
    if kept > 0
      window = f64[kept]
      k = 0 ## i64
      while k < kept
        window[k] = ratios[k]
        k += 1
      interval = Stats.percentile_interval(window)
    Comparison.new(point, interval, kept, a.hit_count.to_f / a.size.to_f - b.hit_count.to_f / b.size.to_f, Stats.percentile_interval(diffs))
