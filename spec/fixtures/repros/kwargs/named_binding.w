# Keyword args bind BY NAME to declared keyword params — order-independent,
# skippable, defaults fire for the ones not given. Historically the compiled
# engine stripped labels and passed values positionally in source order
# (pad("hi", 10, pad_char: "_") put "_" into align), while the interpreter
# collapsed the group into a positional hash. Both now share the
# W_HASH_FLAG_KWARGS remap.
fn show(v)
  v == nil ? "~" : v.to_s()

+ Padder
  -> new
    @seen = 0
  -> pad(s, w, align: "left", pad_char: " ")
    << "pad " + s + "/" + w.to_s() + " align=" + show(align) + " pc=<" + show(pad_char) + ">"

p = Padder.new
p.pad("hi", 10, align: "right")
p.pad("hi", 10, pad_char: "_")
p.pad("hi", 10, pad_char: "*", align: "mid")
p.pad("hi", 10)
