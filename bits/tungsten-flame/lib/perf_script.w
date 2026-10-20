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

use folded

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
    Tungsten:Flame:Folded.emit(stacks)

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
    nonempty = s.split(" ").select -> (p) p.size() > 0
    if nonempty.size() < 2
      return nil
    name = nonempty[1]
    plus_idx = name.rindex("+")
    if plus_idx != nil
      name = name.slice(0, plus_idx)
    if name.size() == 0
      return nil
    name
