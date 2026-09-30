# pgfplots data files of a Scoring: whitespace separated columns under a header
# line of column names, ready for `table[x=..., y=...]`.
use core/file
use core/system
use format
use report
use stats
use proc

+ Pgf
  # A file-name safe form of an algorithm and a task.
  -> .slug(name)
    name.replace("/", ".").replace("@", "_at_")

  -> .rows(header, rows)
    out = [header]
    rows.each -> (row)
      out.push(row.join(" "))
    out.join("\n") + "\n"

  -> .num(x) (f64)
    Format.trimmed(x, 6)

  # Median and quartile rank against CPU seconds on the log-spaced grid.
  -> .descent(scoring, task, algo, points, decades)
    rows = scoring.sample(task, algo).descent(points, decades).map -> (row)
      [Pgf.num(row[0]), Pgf.num(row[2]), Pgf.num(row[1]), Pgf.num(row[3])]
    Pgf.rows("t median q25 q75", rows)

  # Kaplan-Meier survival of the time to target as a step function (constant plot corners).
  -> .survival(scoring, task, algo)
    curve = scoring.sample(task, algo).survival
    budget = scoring.budget(task).to_f ## f64
    rows = [["0", "1"]]
    curve.times.each_with_index -> (t, i)
      rows.push([Pgf.num(t), Pgf.num(curve.levels[i])])
    last = curve.levels.size == 0 ? 1.0 : curve.levels[curve.levels.size - 1]
    rows.push([Pgf.num(budget), Pgf.num(last)])
    Pgf.rows("t survival", rows)

  # The performance profile of one algorithm as a step function of the factor tau.
  -> .profile(scoring, profile, algo, limit)
    rows = [["1", "0"]]
    covered = "0"
    steps = profile.steps(algo)
    i = 0 ## i64
    while i < steps.size
      rows.push([Pgf.num(steps[i][0]), covered])
      covered = Pgf.num(steps[i][1])
      rows.push([Pgf.num(steps[i][0]), covered])
      i += 1
    rows.push([Pgf.num(limit.to_f), covered])
    Pgf.rows("tau rho", rows)

  # Writes every data file into `dir`; returns the number of files.
  -> .write_all(scoring, dir, points, decades)
    File.mkdir_p(dir)
    count = 0
    profile = scoring.profile
    scoring.algos.each -> (algo)
      write_file(dir + "/profile_" + Pgf.slug(algo) + ".dat", Pgf.profile(scoring, profile, algo, 10))
      count += 1
      scoring.tasks.each -> (task)
        if scoring.has?(task, algo)
          write_file(dir + "/descent_" + Pgf.slug(algo) + "_" + Pgf.slug(task) + ".dat", Pgf.descent(scoring, task, algo, points, decades))
          write_file(dir + "/survival_" + Pgf.slug(algo) + "_" + Pgf.slug(task) + ".dat", Pgf.survival(scoring, task, algo))
          count += 2
    count
