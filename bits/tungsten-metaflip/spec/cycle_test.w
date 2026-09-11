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
if ffcy_optimal_rank("2x2") != 7 || ffcy_optimal_rank("2x2x9") != 32 || ffcy_optimal_rank("2x3x4") != 20 || ffcy_optimal_rank("3x3") != 0
  exit(1)
if ffpr_exact_rank(3,2,3) != 15 || ffpr_exact_rank(9,2,2) != 32 || ffpr_exact_rank(4,3,2) != 20 || ffpr_exact_rank(1,7,5) != 35
  exit(1)
if ffpr_exact_rank(3,3,4) != 0 || ffpr_exact_rank(0,2,2) != 0 || ffpr_exact_rank(2,2,33) != 0
  exit(1)
if ffcy_parent_seconds(60,0,0) != 15 || ffcy_parent_seconds(60,1,0) != 7 || ffcy_parent_seconds(60,2,0) != 3 || ffcy_parent_seconds(60,2,1) != 30 || ffcy_parent_seconds(1,0,1) != 1
  exit(1)
root = "/tmp/metaflip-cycle-utility-" + ccall("__w_clock_ms").to_s()
meta = i64[5]
if ffcy_parent_budget(root,60,meta) != 15 || ffcy_parent_budget(root,60,meta) != 15
  exit(1)
z = ffcy_parent_complete(root,meta[2])
if ffcy_parent_budget(root,60,meta) != 7
  exit(1)
z = ffcy_parent_complete(root,meta[2])
if ffcy_parent_budget(root,60,meta) != 3
  exit(1)
z = ffrf_atomic(root + "/submitted","1\n","test")
if ffcy_parent_budget(root,60,meta) != 3 || meta[3] != 1
  exit(1)
if ffcu_source(root,2,2,2) != 1
  exit(1)
# Synthetic telemetry inputs exercise monotonic, permutation-aware credit.
# Actual production calls are downstream of full tensor verification.
id1 = "1" * 64
id2 = "2" * 64
if ffcu_record(root,id1,7,2,2,2) != 1 || File.exists?(root + "/composition/utility/best/2x2x2")
  exit(1)
if ffcu_record(root,id1,22,2,3,4) != 1 || ffmd_count(root + "/composition/utility/saved") != 0
  exit(1)
if ffcu_record(root,id2,21,4,2,3) != 1 || ffmd_count(root + "/composition/utility/saved") != 1
  exit(1)
if ffcu_record(root,id2,21,3,4,2) != 1 || ffcu_record(root,id1,22,2,3,4) != 1 || ffmd_count(root + "/composition/utility/saved") != 1
  exit(1)
if ffcy_parent_budget(root,60,meta) != 30 || meta[1] != 0
  exit(1)
z = ffrf_atomic(root + "/consumed","1\n","test")
z = File.mkdir_p(root + "/composition/mixed")
z = ffrf_atomic(root + "/composition/mixed/parent-submitted","1\n","test")
z = ffcy_parent_complete(root,meta[2])
if ffcy_parent_budget(root,60,meta) != 15 || meta[1] != 0 || meta[3] != 27
  exit(1)
z = ffrf_atomic(root + "/composition/mixed/context","bad\n","test")
z = ffcy_parent_complete(root,meta[2])
if ffcy_parent_budget(root,60,meta) != 15 || meta[1] != 0 || meta[3] != 0-1
  exit(1)
if ffcu_source(root,3,3,3) != 1 || File.read_prefix(root + "/composition/utility/source",64) != "mixed\n"
  exit(1)
if ffcu_record(root,id2,20,2,3,4) != 1 || ffmd_count(root + "/composition/utility/saved") != 1
  exit(1)
if ffcu_record(root,"bad",18,2,3,4) != 0 || ffcu_record(root,id1,0,2,3,4) != 0
  exit(1)
z = ffrf_atomic(root + "/composition/utility/cycle","garbage\n","test")
if ffcy_parent_budget(root,60,meta) != 15 || meta[4] != 1
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
