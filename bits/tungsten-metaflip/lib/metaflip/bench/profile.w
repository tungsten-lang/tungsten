# Dolan-More performance profiles and geometric means of ERT ratios across
# tasks (bench/README.md, section 7, item 6).
use stats

+ Profile
  # `erts[task][algo]`: the ERT of every algorithm on every task, infinite when
  # unsolved. A task enters the profile when some algorithm solves it.
  -> new(@tasks, @algos, @erts)
    @included = []
    @best = {}
    @tasks.each -> (task)
      least = Stats.inf()
      @algos.each -> (algo)
        value = @erts[task][algo]
        least = value if value != nil && value < least
      if least != Stats.inf()
        @included.push(task)
        @best[task] = least

  -> included
    @included

  # The ERT ratios to the best algorithm of algo, over the included tasks it solves; ascending.
  -> ratios(algo)
    out = []
    @included.each -> (task)
      value = @erts[task][algo]
      out.push(value / @best[task]) if value != nil && value != Stats.inf()
    out.sort

  # The fraction of included tasks on which algo is within a factor tau of the best.
  -> rho(algo, tau)
    limit = tau.to_f ## f64
    ratios = self.ratios(algo)
    count = 0 ## i64
    i = 0 ## i64
    while i < ratios.size
      count += 1 if ratios[i] <= limit
      i += 1
    count.to_f / @included.size.to_f

  # The steps of the profile: [tau, rho] at each distinct ratio, ascending.
  -> steps(algo)
    out = []
    ratios = self.ratios(algo)
    i = 0 ## i64
    while i < ratios.size
      j = i ## i64
      while j + 1 < ratios.size && ratios[j + 1] == ratios[i]
        j += 1
      out.push([ratios[i], (j + 1).to_f / @included.size.to_f])
      i = j + 1
    out

  # Geometric mean of the ERT ratios of algo to ref over the tasks both solve:
  # [value or nil, task count].
  -> geomean(algo, ref)
    total = 0.0 ## f64
    count = 0 ## i64
    @tasks.each -> (task)
      a = @erts[task][algo]
      b = @erts[task][ref]
      if a != nil && b != nil && a != Stats.inf() && b != Stats.inf()
        total = total + Math.log(a / b)
        count += 1
    return [nil, 0] if count == 0
    [Math.exp(total / count.to_f), count]
