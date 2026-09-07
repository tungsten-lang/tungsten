use ../../compiler/lib/content_hash

-> check(name, got, want)
  if got != want
    << "FAIL content hash " + name + " got=" + got + " want=" + want
    exit(1)
  << "PASS content hash " + name

-> encoded(value, temp_map)
  buf = StringBuffer(32)
  encode_val(buf, value, temp_map)
  buf.to_s()

-> encoded_instruction(inst)
  buf = StringBuffer(128)
  temp_map = ccall_rawargs("w_content_temp_map_new", 64, 0)
  encode_inst(inst, buf, temp_map, {}, {}, {string_index: {}}, "__self", {})
  buf.to_s()

+ PercentText
  -> to_s
    "%custom"

temps = ccall_rawargs("w_content_temp_map_new", 64, 0)
check("temp first", encoded("%t42", temps), "t0,")
check("temp repeat", encoded("%t42", temps), "t0,")
check("literal string", encoded("literal", temps), "lliteral,")
check("empty string", encoded("", temps), "l,")
check("integer fallback", encoded(17, temps), "l17,")
check("symbol fallback", encoded(:alpha, temps), "lalpha,")
check("custom percent fallback", encoded(PercentText.new(), temps), "t1,")

# Recycling changes allocation/release semantics, so two otherwise identical
# constructor bodies must not content-collapse across that boundary.
plain_ctor = wire_instruction({
  op: :call_method_i64,
  temp: "%result",
  receiver: "%klass",
  method_name_val: "0",
  args: ["%arg"],
  construct_class: "HashPoint",
  construct_fn: "__w_HashPoint_new__a2"
})
recycled_ctor = wire_clone_instruction(plain_ctor)
wire_set(recycled_ctor, :construct_recycle, true)
plain_encoding = encoded_instruction(plain_ctor)
recycled_encoding = encoded_instruction(recycled_ctor)
if plain_encoding == recycled_encoding || !recycled_encoding.include?(":recycle")
  << "FAIL content hash constructor recycle identity"
  exit(1)
<< "PASS content hash constructor recycle identity"
