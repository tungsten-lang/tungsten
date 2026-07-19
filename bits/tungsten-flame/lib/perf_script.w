# perf_script.w — parse `perf script` output into folded-stack format.
#
# Replaces the `inferno-collapse-perf` Rust binary. A `perf script` sample
# block looks like:
#
#   program  12345 [001] 1234.567890: 1000000 cycles:
#           ffffffff8101a1c0 do_syscall_64+0x44 ([kernel.kallsyms])
#           00007fff6e521234 __libc_start_main+0xf0 (/usr/lib/libc.so.6)
#           0000000000401234 main+0x12 (/path/to/binary)
#
# A blank line separates samples. `perf` lists frames leaf-to-root; the
# folded-stack format wants root-to-leaf, so we reverse before joining.
# Identical stacks get merged with summed sample counts.

in Tungsten:Flame

+ PerfScript

  # Parse perf-script text → folded-stack string ("root;...;leaf <count>" per line).
  # Output is sorted by stack name for deterministic golden-file comparisons.
  -> .collapse(text)
    lines = text.split("\n")
    stacks = {}
    current = []
    i = 0
    n = lines.size()
    while i < n
      line = lines[i]
      stripped = line.strip()
      if stripped.size() == 0
        self.flush(current, stacks)
        current = []
      else
        first_char = line.slice(0, 1)
        if first_char != "\t" && first_char != " "
          # Header line for a new sample — flush whatever we accumulated.
          self.flush(current, stacks)
          current = []
        else
          frame = self.parse_frame(stripped)
          if frame != nil
            current.push(frame)
      i = i + 1
    self.flush(current, stacks)

    keys = stacks.keys()
    sorted_keys = self.sort_strings(keys)
    out = []
    j = 0
    while j < sorted_keys.size()
      k = sorted_keys[j]
      out.push(k + " " + stacks[k].to_s())
      j = j + 1
    out.join("\n")

  -> .flush(frames, stacks)
    if frames.size() == 0
      return
    folded = frames.reverse().join(";")
    if stacks.has_key?(folded)
      stacks[folded] = stacks[folded] + 1
    else
      stacks[folded] = 1

  # "addr function+offset (lib_path)" → "function".
  # "addr [unknown] ..." → "[unknown]".
  -> .parse_frame(s)
    parts = s.split(" ")
    # Filter empties from runs of whitespace.
    nonempty = []
    pi = 0
    while pi < parts.size()
      if parts[pi].size() > 0
        nonempty.push(parts[pi])
      pi = pi + 1
    if nonempty.size() < 2
      return nil
    name = nonempty[1]
    plus_idx = name.rindex("+")
    if plus_idx != nil
      name = name.slice(0, plus_idx)
    if name.size() == 0
      return nil
    name

  # Tungsten hashes preserve insertion order, but our test compares to a
  # checked-in golden file. Sort lexicographically for reproducibility.
  -> .sort_strings(xs)
    arr = []
    i = 0
    while i < xs.size()
      arr.push(xs[i])
      i = i + 1
    j = 1
    while j < arr.size()
      key = arr[j]
      k = j - 1
      while k >= 0 && arr[k] > key
        arr[k + 1] = arr[k]
        k = k - 1
      arr[k + 1] = key
      j = j + 1
    arr
