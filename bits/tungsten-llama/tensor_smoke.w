# P5.2 smoke: load qwen3, build Tensor wrappers, peek into the
# first Q8_0 block of `output.weight` to verify offsets land on
# real data (not metadata).

use lib/gguf
use lib/tensor

GGUF_PATH = "/Users/erik/.ollama/models/blobs/sha256-ae354763fe478c790125fb993e59bb1266655b3fa721eebe4a931660c3ed2ce9"

g = GGUF.new(GGUF_PATH)

# Wrap a Q8_0 tensor — output.weight = lm_head, [2048, 151936].
output_desc = g.tensor("output.weight")
if output_desc == nil
  << "FAIL no output.weight"
  exit 1
output = Tensor.new(g, output_desc)

<< "tensor: " + output.to_s
<< "  elements: " + output.element_count.to_s

# Q8_0 layout per 32-element block:
#   bytes 0..1   f16 scale
#   bytes 2..33  i8 quants
# Sanity-check the first block of output.weight.
scale_bits = output.u16_at(0)
<< "  block 0 scale_bits=" + scale_bits.to_s + " (u16; decode to f16 = TODO)"

i = 0
out_str = StringBuffer(128)
out_str << "  block 0 quants: ["
while i < 32
  if i > 0
    out_str << ", "
  out_str << output.i8_at(2 + i).to_s
  i = i + 1
out_str << "]"
<< out_str.to_s

# Sanity: quants in [-127, 127].
ok = true
i = 0
while i < 32
  q = output.i8_at(2 + i)
  if q < -127 || q > 127
    ok = false
  i = i + 1
if !ok
  << "FAIL quant out of range"
  exit 1

# Try a F16 tensor too: blk.0.attn_v.weight is F16 [2048, 512].
vw = g.tensor("blk.0.attn_v.weight")
v = Tensor.new(g, vw)
<< "tensor: " + v.to_s
<< "  first f16: 0x" + v.u16_at(0).to_s

# And a tiny F32 tensor: blk.0.attn_norm.weight is F32 [2048].
nw = g.tensor("blk.0.attn_norm.weight")
n = Tensor.new(g, nw)
<< "tensor: " + n.to_s
b0 = n.byte_at(0)
b1 = n.byte_at(1)
b2 = n.byte_at(2)
b3 = n.byte_at(3)
bits = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
v0 = Float.from_u32_bits(bits)
<< "  first f32: " + v0.to_s

<< "OK"
g.close
