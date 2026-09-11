use ../lib/metaflip/cycle
use core/system

av = argv()
if av.size() > 0 && av[0] == "exec-child"
  if av.size() != 42
    exit(1)
  i = 1 ## i64
  while i < av.size()
    expected = "arg " + i.to_s() + " ' $ odd"
    if av[i] != expected
      exit(1)
    i += 1
  << "PASS cycle exec preserves all argument bytes"
  exit(0)

labels = ffcy_default_shapes()
if labels.size() != 34 || labels[0] != "2x2" || labels[5] != "7x7" || labels[33] != "5x6x7"
  exit(1)
i = 0 ## i64
while i < labels.size()
  j = i + 1 ## i64
  while j < labels.size()
    if labels[i] == labels[j]
      exit(1)
    j += 1
  i += 1
parsed = []
if ffcy_parse_shapes("05X05, 2x2x5,7x7", parsed) != 3 || parsed[0] != "5x5"
  exit(1)
bad = ["5x5,05x05", "4x4,", ",4x4", "4x4,,5x5", "4x4, ,5x5", "8x8", "5junkx5junk"]
i = 0
while i < bad.size()
  invalid = []
  if ffcy_parse_shapes(bad[i], invalid) != 0
    exit(1)
  i += 1
if ffcy_slice_seconds(60, 0, 100) != 60 || ffcy_slice_seconds(60, 1101, 100) != 2 || ffcy_slice_seconds(60, 100, 100) != 0
  exit(1)
if ffcy_slice_seconds(60, 9223372036854775807, 0) != 60
  exit(1)
args = ["--no-gpu", "-J", "16", "--secs", "120", "--cycle-position", "3", "--cycle-deadline-ms", "1000"]
next_args = ffcy_next_argv("metaflip", args, 4, 1000, ["-J", "--secs"])
expected = ["metaflip", "--no-gpu", "-J", "16", "--secs", "120", "--cycle-position", "4", "--cycle-deadline-ms", "1000"]
if next_args != expected
  exit(1)
quoted = ffcy_next_argv("metaflip", ["--status", "--cycle-position"], 2, 0, ["--status"])
if quoted[2] != "--cycle-position" || quoted.size() != 7
  exit(1)
<< "PASS cycle schedule, parsing, limits and forwarding"
child = [System.executable_path(), "exec-child"]
i = 1
while i <= 41
  child.push("arg " + i.to_s() + " ' $ odd")
  i += 1
flush()
exit(ffcy_exec(child))
