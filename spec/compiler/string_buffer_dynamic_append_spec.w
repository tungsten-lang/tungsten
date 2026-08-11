# Dynamic StringBuffer appends inside functions must take the same direct
# runtime path as literal appends. Unknown parameter/local types used to fall
# through the bodiless Core method and silently append nothing when compiled.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> render(prefix, suffix)
  sb = StringBuffer(4)
  local = prefix
  joined = "-" + suffix
  sb.append(local)
  sb.append(joined)
  sb << 42
  sb.to_s()

check("strbuf.dynamic_param_local_concat", render("alpha", "omega"), "alpha-omega42")
