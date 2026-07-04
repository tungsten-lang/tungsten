# Per-file tokenizer benchmark.
#
# Reads a list of file paths (one per line), pre-reads all contents,
# then times the tokenization of each file. Run seq and parallel.
#
# Usage:
#   bin/tungsten compile languages/openai/bench_files.w --out /tmp/tt_bench_files
#   /tmp/tt_bench_files <vocab.tiktoken> <filelist> [workers] [mode]
#     mode: seq (default) | par

use ./tokenizer

args = argv()
if args.size() < 2
  << "usage: bench_files <vocab.tiktoken> <filelist> [workers] [mode]"
  << "  mode: seq (default) | par"
  exit(1)

vocab = args[0]
list_path = args[1]
workers = 0
if args.size() > 2
  workers = args[2].to_i()
mode = "seq"
if args.size() > 3
  mode = args[3]

<< "Loading vocabulary..."
tok = load_tokenizer(vocab)
freeze_slab()
<< "  [tok[:size]] tokens"

<< "Reading file list..."
listing = read_file(list_path)
lines = listing.split("\n")
files = []
lines.each -> (p)
  if p.size() > 0
    files.push(p)

<< "  [files.size()] files"

<< "Pre-reading contents..."
contents = []
total_bytes = 0
i = 0
while i < files.size()
  t = read_file(files[i])
  contents.push(t)
  total_bytes += t.size()
  i += 1

<< "  [total_bytes] bytes total"
<< ""
<< "Benchmark"
<< "  mode:    [mode]"
<< "  workers: [workers]"

if mode == "par" && workers > 0
  ccall("w_scheduler_start", workers)

t0 = clock()
total_tokens = 0

if mode == "par" && workers > 0
  nf = contents.size()
  work = Channel.new(workers)
  results = Channel.new(workers)

  w = 0
  while w < workers
    ws = (nf * w) / workers
    we = (nf * (w + 1)) / workers
    work.send({start: ws, end: we})
    w += 1

  w = 0
  while w < workers
    go ->
      m = work.recv()
      count = 0
      k = m[:start]
      while k < m[:end]
        ids = encode(tok, contents[k])
        count += ids.size()
        k += 1
      results.send(count)
    w += 1

  got = 0
  while got < workers
    total_tokens += results.recv()
    got += 1
else
  k = 0
  while k < contents.size()
    ids = encode(tok, contents[k])
    total_tokens += ids.size()
    k += 1

elapsed = clock() - t0

if mode == "par" && workers > 0
  ccall("w_scheduler_stop")

<< ""
<< "  tokens:     [total_tokens]"
<< "  time:       [elapsed]ms"
if elapsed > 0
  throughput = (total_bytes * 1000) / (elapsed * 1024 * 1024)
  << "  throughput: [throughput] MiB/s"
  tps = (total_tokens * 1000) / elapsed
  << "  tokens/sec: [tps]"
