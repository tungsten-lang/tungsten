in Tungsten:Llama

QWEN3_30B_A3B_Q8_0 = "qwen3:30b-a3b-q8_0"

-> model_gate_value_s(value)
  if value == nil
    "(missing)"
  else
    value.to_s

-> model_gate_require(g, model_name, key, expected)
  got = g.metadata[key]
  if got != expected
    raise model_name + " gate failed: expected " + key + " = " + expected.to_s + ", got " + model_gate_value_s(got)

-> model_gate_require_tensor(g, model_name, tensor_name, type_name)
  t = g.tensor(tensor_name)
  if t == nil
    raise model_name + " gate failed: missing tensor " + tensor_name
  if t[:type_name] != type_name
    raise model_name + " gate failed: expected " + tensor_name + " type " + type_name + ", got " + t[:type_name]

-> model_gate_require_tensor_shape(g, model_name, tensor_name, shape)
  t = g.tensor(tensor_name)
  if t == nil
    raise model_name + " gate failed: missing tensor " + tensor_name
  if t[:shape].size() != shape.size()
    raise model_name + " gate failed: expected " + tensor_name + " rank " + shape.size().to_s + ", got " + t[:shape].size().to_s
  i = 0
  while i < shape.size()
    if t[:shape][i] != shape[i]
      raise model_name + " gate failed: expected " + tensor_name + " dim " + i.to_s + " = " + shape[i].to_s + ", got " + t[:shape][i].to_s
    i = i + 1

-> require_qwen3_30b_a3b_q8_0(g)
  model_gate_require(g, QWEN3_30B_A3B_Q8_0, "general.architecture", "qwen3moe")
  model_gate_require(g, QWEN3_30B_A3B_Q8_0, "qwen3moe.block_count", 48)
  model_gate_require(g, QWEN3_30B_A3B_Q8_0, "qwen3moe.embedding_length", 2048)
  model_gate_require(g, QWEN3_30B_A3B_Q8_0, "qwen3moe.feed_forward_length", 6144)
  model_gate_require(g, QWEN3_30B_A3B_Q8_0, "qwen3moe.expert_feed_forward_length", 768)
  model_gate_require(g, QWEN3_30B_A3B_Q8_0, "qwen3moe.expert_count", 128)
  model_gate_require(g, QWEN3_30B_A3B_Q8_0, "qwen3moe.expert_used_count", 8)
  model_gate_require(g, QWEN3_30B_A3B_Q8_0, "qwen3moe.attention.head_count", 32)
  model_gate_require(g, QWEN3_30B_A3B_Q8_0, "qwen3moe.attention.head_count_kv", 4)
  model_gate_require(g, QWEN3_30B_A3B_Q8_0, "qwen3moe.attention.key_length", 128)
  model_gate_require(g, QWEN3_30B_A3B_Q8_0, "qwen3moe.attention.value_length", 128)

  model_gate_require_tensor(g, QWEN3_30B_A3B_Q8_0, "token_embd.weight", "Q8_0")
  model_gate_require_tensor(g, QWEN3_30B_A3B_Q8_0, "output.weight", "Q8_0")
  model_gate_require_tensor(g, QWEN3_30B_A3B_Q8_0, "blk.0.attn_q.weight", "Q8_0")
  model_gate_require_tensor(g, QWEN3_30B_A3B_Q8_0, "blk.0.attn_v.weight", "F16")
  model_gate_require_tensor(g, QWEN3_30B_A3B_Q8_0, "blk.0.ffn_gate_inp.weight", "F32")
  model_gate_require_tensor_shape(g, QWEN3_30B_A3B_Q8_0, "token_embd.weight", [2048, 151936])
  model_gate_require_tensor_shape(g, QWEN3_30B_A3B_Q8_0, "output.weight", [2048, 151936])
  model_gate_require_tensor_shape(g, QWEN3_30B_A3B_Q8_0, "blk.0.attn_q.weight", [2048, 4096])
  model_gate_require_tensor_shape(g, QWEN3_30B_A3B_Q8_0, "blk.0.attn_v.weight", [2048, 512])
  model_gate_require_tensor_shape(g, QWEN3_30B_A3B_Q8_0, "blk.47.ffn_norm.weight", [2048])
  true
