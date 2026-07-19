# Carbide::Serializer — JSON serialization for API responses.
#
# A pure-Tungsten JSON encoder plus Model conveniences:
#
#   Serializer.encode({id: 1, title: "hi"})   # => "{\"id\":1,\"title\":\"hi\"}"
#   Serializer.record(post)                    # post.to_h as a JSON object
#   Serializer.collection(posts)               # array of to_h as a JSON array
#
# Why not core JSON.encode: it is compiled-only today — its container
# branches iterate with the implicit-each form (`value -> ...`), which
# the self-hosted interpreter does not bind (`Undefined variable or
# method 'item'`). The tungsten-json bit only accelerates JSON.parse
# (and `use json` currently breaks compiled linking). This encoder is
# the same shape as core's but with explicit `.each -> (x)` blocks, so
# it produces identical output on BOTH engines. Decoding is core
# JSON.parse — compiled-only, string keys.
#
# Encoding rules: Hash -> object (keys stringified), Array -> array,
# String/Symbol -> string (escaped), Integer/Float -> number,
# true/false/nil -> literals, anything else -> to_s as a string.
#
# Top-level (no `in` namespace): same convention as route.w / model.w.

+ Serializer
  # Encode any Tungsten value as a JSON string.
  -> .encode(value)
    t = type(value)
    out = ""
    if value == nil
      out = "null"
    elsif t == "Boolean"
      if value
        out = "true"
      else
        out = "false"
    elsif t == "Integer" || t == "Float" || t == "Decimal"
      out = value.to_s
    elsif t == "String"
      out = Serializer.encode_string(value)
    elsif t == "Symbol"
      out = Serializer.encode_string(value.to_s)
    elsif t == "Array"
      parts = []
      value.each -> (item)
        parts.push(Serializer.encode(item))
      out = "\[" + parts.join(",") + "\]"
    elsif t == "Hash"
      parts = []
      keys = value.keys
      keys.each -> (k)
        parts.push(Serializer.encode_string(k.to_s) + ":" + Serializer.encode(value[k]))
      out = "{" + parts.join(",") + "}"
    else
      out = Serializer.encode_string(value.to_s)
    out

  # Quote and escape one string. Fast path when nothing needs escaping;
  # the escape set matches the per-character loop exactly.
  -> .encode_string(s)
    raw = s.to_s
    result = ""
    if !raw.include?("\"") && !raw.include?("\\") && !raw.include?("\n") && !raw.include?("\r") && !raw.include?("\t")
      result = "\"" + raw + "\""
    else
      out = "\""
      chars = raw.chars
      i = 0
      while i < chars.size
        ch = chars[i]
        if ch == "\""
          out = out + "\\\""
        elsif ch == "\\"
          out = out + "\\\\"
        elsif ch == "\n"
          out = out + "\\n"
        elsif ch == "\r"
          out = out + "\\r"
        elsif ch == "\t"
          out = out + "\\t"
        else
          out = out + ch
        i += 1
      result = out + "\""
    result

  # --- Model conveniences ---

  # One model -> JSON object (via Model#to_h).
  -> .record(model)
    Serializer.encode(model.to_h)

  # Array of models -> JSON array of objects.
  -> .collection(models)
    rows = []
    models.each -> (m)
      rows.push(m.to_h)
    Serializer.encode(rows)
