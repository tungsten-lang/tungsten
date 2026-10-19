# spec: compiled -- exercises the ownership pass's fresh heap results
# compiler/lib/ownership.w fresh_heap_returns: a function whose every return
# is a newly built array or string that nothing else in it keeps hands its
# caller a value the caller owns.  Container writes keep the stored value but
# not the container (container_store_first_kept), and read-only Array, String
# and Hash methods keep nothing (runtime_types.w container_reader_method?).
# Every shape that must keep a value alive is checked, then the memory of a
# loop that builds and drops arrays is bounded.

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> zeros(n)
  a = []
  i = 0
  while i < n
    a.push(0)
    i += 1
  a

-> copy_list(a)
  out = []
  i = 0
  while i < a.size
    out.push(a[i])
    i += 1
  out

saved_box = []

-> saved_copy(a)
  c = copy_list(a)
  saved_box.push(c)
  c

-> sizes(n)
  acc = 0
  i = 0
  while i < n
    z = zeros(64)
    c = copy_list(z)
    h = {a: i, b: i + 1}
    acc += z.size + c.size + h.size + [i, i, i].size
    i += 1
  acc

-> containers_keep(n)
  outer = []
  i = 0
  while i < n
    inner = zeros(3)
    inner[0] = i
    outer.push(inner)
    i += 1
  outer

check("arrays and hashes built and dropped in a loop", sizes(100) == 100 * (64 + 64 + 2 + 3))
ck = containers_keep(10)
check("an array stored in another stays valid", ck.size == 10 && ck[9][0] == 9 && ck[0].size == 3)
sc = saved_copy([1, 2, 3])
check("a fresh result its function also stores stays valid", sc == [1, 2, 3] && saved_box[0] == [1, 2, 3])

# Memory: 200,000 rounds of zeros(64) + copy_list kept every array before (about
# 220 MB); now each is freed at the end of its iteration.
total = sizes(200_000)
rss_kib = OS.capture("ps -o rss= -p $PPID").strip().to_i()
check("200,000 rounds stay under 40 MB (rss_kib=[rss_kib])", rss_kib > 0 && rss_kib < 40_960)
check("and the count is right", total == 200_000 * 133)
<< "fresh_heap_release_spec: all checks passed"
