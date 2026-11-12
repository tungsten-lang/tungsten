# The order in which an experiment runs its jobs. Within each task the seeds
# are blocks; blocks and the algorithms inside a block are shuffled with a
# seeded generator, so background load reaches every algorithm alike. The
# generator draws the same numbers whatever has finished, so a resumed
# experiment continues the same order.
use stats
use record

+ Plan
  # Fisher-Yates shuffle in place; returns the array.
  -> .shuffle(items, cell)
    i = items.size - 1 ## i64
    while i > 0
      j = Stats.pick(cell, i + 1) ## i64
      held = items[i]
      items[i] = items[j]
      items[j] = held
      i -= 1
    items

  # Keys (Record.key) of the runs that need no repetition: every record of the
  # experiment, or only the `ok` ones when errors are retried.
  -> .finished(experiment, records, retry_errors)
    done = {}
    records.each -> (rec)
      if rec["experiment"] == experiment && (!retry_errors || rec["status"] == "ok")
        done[Record.key(rec)] = true
    done

  # Jobs {algo, task, index, seed} of the runs not finished yet. `count` seeds
  # per task (nil: the task's own `runs`).
  -> .jobs(experiment, algos, tasks, count, order_seed, done)
    cell = Stats.generator(order_seed)
    jobs = []
    tasks.each -> (task)
      total = count == nil ? task.runs : count
      blocks = []
      i = 0 ## i64
      while i < total
        blocks.push(i)
        i += 1
      Plan.shuffle(blocks, cell)
      blocks.each -> (index)
        seed = task.seed_base + index
        arms = []
        algos.each -> (algo)
          arms.push(algo)
        Plan.shuffle(arms, cell)
        arms.each -> (algo)
          key = experiment + "|" + algo.name + "|" + task.id + "|" + seed.to_s
          jobs.push({"algo" => algo, "task" => task, "index" => index, "seed" => seed}) if !done.key?(key)
    jobs
