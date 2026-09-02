# Tokenize a text file into the JSON id array the LLM engines take as their
# prompt-ids argument (qwen38fn_mlx.w ARGV[3], qwen38_mlx.w `multi auto`).
#
#   prep_ids <text_file> <n_tokens|0 = all> <out.json> [tokenizer.json.bin]
#
# Plain BPE encode: special tokens in the text are NOT recognized (the chat
# server splices them by id). Default tokenizer = the flash-next pack.
use tungsten-llama/tokenizer

src = ARGV[0]
n_keep = ARGV[1].to_i
out = ARGV[2]
tok_path = "/Users/erik/.cache/tungsten/qwen38-flash-next-nvfp4/tokenizer.json.bin"
if ARGV.size() > 3 then tok_path = ARGV[3]
tok = Tungsten:Llama:Tokenizer.from_packed_tokenizer(tok_path)
all_ids = tok.encode(read_file(src))
ids = all_ids
if n_keep > 0 && all_ids.size() > n_keep
  ids = []
  i = 0
  while i < n_keep
    ids.push(all_ids[i])
    i = i + 1
File.write(out, ids.to_s)
<< "wrote " + ids.size().to_s + " ids (of " + all_ids.size().to_s + ") to " + out
