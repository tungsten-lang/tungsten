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

+ PercentText
  -> to_s
    "%custom"

temps = {next_idx: 0}
check("temp first", encoded("%t42", temps), "t0,")
check("temp repeat", encoded("%t42", temps), "t0,")
check("literal string", encoded("literal", temps), "lliteral,")
check("empty string", encoded("", temps), "l,")
check("integer fallback", encoded(17, temps), "l17,")
check("symbol fallback", encoded(:alpha, temps), "lalpha,")
check("custom percent fallback", encoded(PercentText.new(), temps), "t1,")
