# Timing of jsonx.w / floatx.w on the real matmulcatalog table (10.7 MB):
#
#   tungsten -o json_bench spec/gf2_support/json_bench.w --release
#   ./json_bench work/mmc_catalog_0929.json spec/fixtures/gf2_support/json/floats.tsv
#
# Medians of 5 runs, in seconds. json_bench.py prints the same lines for Python's json
# module (json.loads, json.dumps(indent=1)) and float repr; core/json.w's
# JSON.parse is timed as the baseline this reader replaces.
use core/json
use ../../lib/metaflip/gf2/jsonx
use floatx_cases

-> bench_median(values)
  sorted = values.sort
  sorted[sorted.size / 2]

catalog = read_file(argv()[0])
runs = 5
times = []
runs.times -> (i)
  t0 = clock()
  tree = JSON.parse(catalog)
  times.push(clock() - t0)
<< "core JSON.parse catalog      " + Floatx.fixed(bench_median(times), 4)
times = []
runs.times -> (i)
  t0 = clock()
  tree = Jsonx.loads(catalog)
  times.push(clock() - t0)
<< "Jsonx.loads catalog          " + Floatx.fixed(bench_median(times), 4)
tree = Jsonx.loads(catalog)
times = []
runs.times -> (i)
  t0 = clock()
  text = Jsonx.dumps(tree, indent: 1)
  times.push(clock() - t0)
<< "Jsonx.dumps indent=1 catalog " + Floatx.fixed(bench_median(times), 4)
times = []
runs.times -> (i)
  t0 = clock()
  text = Jsonx.dumps(tree)
  times.push(clock() - t0)
<< "Jsonx.dumps default catalog  " + Floatx.fixed(bench_median(times), 4)
floats = []
read_file(argv()[1]).split("\n").each -> (line)
  floats.push(gf2_float_from_hex(line.split("\t")[0])) if line.size > 0
times = []
runs.times -> (i)
  t0 = clock()
  floats.each -> (x)
    Floatx.repr(x)
  times.push(clock() - t0)
<< "Floatx.repr " + floats.size.to_s + " doubles     " + Floatx.fixed(bench_median(times), 4)
