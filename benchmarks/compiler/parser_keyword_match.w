use ../../compiler/lib/parser

+ ParserKeywordBench < Parser
  -> new

-> bench_keyword_match(n)
  type_scale = 274877906944
  length_scale = 67108864
  token = 7 * type_scale + 6 * length_scale + 4
  parser = ParserKeywordBench.new()
  parser.set_chars(["é", "r", "e", "s", "c", "u", "e", "!"])
  i = 0 ## i64
  hits = 0
  t0 = clock()
  while i < n
    if parser.tok_equal?(token, "ignored", "rescue")
      hits += 1
    if parser.tok_equal?(token, "ignored", "ensure")
      hits += 2
    i += 1
  t1 = clock()
  << "parser_keyword\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + hits.to_s()

args = argv()
n = args.size() > 0 ? args[0].to_i() : 5000000
bench_keyword_match(n)
