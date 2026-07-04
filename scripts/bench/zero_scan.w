# One-shot statistical scan: count Q8_0 blocks where scale==0 OR all
# 32 quants==0, across the per-expert tensors of one block. Reports
# whether there's exploitable zero-sparsity beyond the top-K routing.

use tungsten-llama/gguf

GGUF_PATH = "/Users/erik/.ollama/models/blobs/sha256-ae354763fe478c790125fb993e59bb1266655b3fa721eebe4a931660c3ed2ce9"

g = GGUF.new(GGUF_PATH)

# Each Q8_0 block = 2-byte f16 scale + 32-byte i8 quants = 34 bytes.
-> scan_q8(name)
  t = g.tensor(name)
  off = g.tensor_file_offset(t)
  nbytes = t.byte_length
  nblocks = nbytes / 34
  zero_scale = 0
  zero_quants = 0
  total = nblocks
  i = 0
  while i < nblocks
    block_off = off + i * 34
    s_lo = g.mmap.byte_at(block_off + 0)
    s_hi = g.mmap.byte_at(block_off + 1)
    if s_lo == 0 && s_hi == 0
      zero_scale = zero_scale + 1
    else
      all_zero = true
      j = 0
      while j < 32
        if g.mmap.byte_at(block_off + 2 + j) != 0
          all_zero = false
          break
        j = j + 1
      if all_zero
        zero_quants = zero_quants + 1
    i = i + 1
  pct_s = (~0.0 + zero_scale * 100) / (~0.0 + total)
  pct_q = (~0.0 + zero_quants * 100) / (~0.0 + total)
  << name + ": " + total.to_s + " blocks, scale==0: " + zero_scale.to_s + " (" + pct_s.to_s + "%), quants==0: " + zero_quants.to_s + " (" + pct_q.to_s + "%)"

<< "scanning block 0 expert + projection tensors..."
scan_q8("blk.0.attn_q.weight")
scan_q8("blk.0.attn_k.weight")
scan_q8("blk.0.attn_output.weight")
scan_q8("blk.0.ffn_gate_exps.weight")
scan_q8("blk.0.ffn_up_exps.weight")
scan_q8("blk.0.ffn_down_exps.weight")
scan_q8("output.weight")
g.close
