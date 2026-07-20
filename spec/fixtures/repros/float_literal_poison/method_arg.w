# A decimal literal passed as a method argument, then converted to Float
# inside the callee. This is the "float literal across a method boundary"
# shape the repo's workaround culture forbade.
-> takes(x)
  x.to_f * 2

+ Ratio
  ro :pct
  -> new(pct = 0)
    @pct = pct
  -> show
    @pct.to_f.to_s

<< "method arg to_f: " + takes(0.1).to_s
r = Ratio.new(0.75)
<< "ctor arg to_f: " + r.show
