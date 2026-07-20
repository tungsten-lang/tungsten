+ ProbeC
  ro :alpha
  -> new(alpha = 0)
    @alpha = alpha
  -> show
    @alpha.to_s

# A float literal used at top level BEFORE the ctor call
a = 1
x = a / 10.0
<< "local x:            " + x.to_s
p1 = ProbeC.new(x.to_f)
<< "ctor x.to_f after float literal: " + p1.show
