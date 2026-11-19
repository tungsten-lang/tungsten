# Usage: assumption_regions plain|regions formula.cnf trace.txt
# The first trace line gives boundary variable IDs. Subsequent lines each
# hold one assumption query. End each line with 0 (an empty query is "0").
use ../lib/assumption_regions

-> region_bench_us
  (ccall("__w_clock") * 1000000).to_i

-> region_bench_row(line)
  tokens = line.strip.split(" ")
  raise "expected a 0-terminated row" unless tokens.size > 0 && tokens.last == "0"
  lits = []
  (0...(tokens.size - 1)).each -> (i)
    lits.push(tokens[i].to_i) unless tokens[i] == ""
  lits

args = argv()
raise "expected plain|regions formula.cnf trace.txt" unless args.size == 3
mode = args[0]
raise "expected plain or regions" unless mode == "plain" || mode == "regions"
formula = wassat_parse_cnf_native(read_file(args[1]))
rows = read_file(args[2]).lines
boundary = region_bench_row(rows[0])
queries = []
(1...rows.size).each -> (i)
  queries.push(region_bench_row(rows[i])) unless rows[i].strip == ""
# Read/parse and reporting are outside the measurements. The setup measurement
# includes constructing the solver and installing all derived clauses.
start = region_bench_us
facts = mode == "regions" ? wassat_region_query_facts(formula, boundary) : []
summarized = region_bench_us
nv = formula["nvars"]
solver = Wassat.from_flat(nv, wassat_raw_artifact(formula, nv), 0)
loaded = region_bench_us
facts.each -> (clause)
  solver.add_input_clause(clause)
ready = region_bench_us

samples = []
sat = 0
unsat = 0
queries.each_with_index -> (query, i)
  result = solver.solve_assuming(query)
  case result["status"]
    when 1
      sat += 1
    when -1
      unsat += 1
    else
      raise "incomplete assumption query"
  n = i + 1
  if n == 1 || n == 8 || n == 64 || n == 256 || n == queries.size
    samples.push([n, region_bench_us - ready, sat, unsat])

<< "mode=[mode] facts=[facts.size] summarize_us=[summarized-start] load_us=[loaded-summarized] attach_us=[ready-loaded] setup_us=[ready-start]"
samples.each -> (sample)
  << "queries=[sample[0]] query_us=[sample[1]] total_us=[ready-start+sample[1]] sat=[sample[2]] unsat=[sample[3]]"
