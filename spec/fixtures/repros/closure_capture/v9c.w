+ Ctl
  ro :req

  -> new(@req)

  -> show
    "shown:" + @req

+ Rt
  ro :klass
  ro :handler

  -> new(@klass)
    k = @klass
    @handler = -> (req)
      c = k.new(req)
      c.show

r = Rt.new(Ctl)
h = r.handler
<< h.call("one")
<< h.call("two")
