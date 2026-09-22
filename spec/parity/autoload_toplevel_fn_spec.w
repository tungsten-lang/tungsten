# A `-> name` outside a class body is a global function, whatever `self`
# happens to be when the definition is evaluated. The cases that matter:
#
# 1. A core class first referenced INSIDE a method autoloads its file while a
#    self object is active; the file's top-level `-> fn`s (core/base64.w's
#    base64_encode/base64_decode here, pf_run in core/algebra/poly_fast.w in
#    the wild) must still be callable from any other self, or none.
# 2. A `->` nested in a method body is hoisted to a global function.
#
# Cross-engine parity spec (scripts/parity.sh).

+ Codec
  -> new
    @label = "codec"
  -> encode(text)
    Base64.encode(text)

+ Other
  -> new
    @label = "other"
  -> roundtrip(text)
    base64_decode(base64_encode(text)).size

encoded = Codec.new.encode("hello")
<< "encoded [encoded]"
<< "top-level decode size [base64_decode(encoded).size]"
word = "parity"
<< "other self roundtrip [Other.new.roundtrip(word)]"

+ Box
  -> new
    @v = 3
  -> install
    -> shout(x)
      "shout " + x.to_s
    shout(@v)

b = Box.new
<< "nested def inside [b.install]"
<< "nested def top-level [shout(7)]"
