+ Ctl
  ro :req

  -> new(@req)

  -> show
    "shown:" + @req

+ Rt
  ro :klass

  -> new(@klass)

+ Mt
  ro :rt

  -> new(@rt)

  -> handler
    rt = @rt
    << "handler sees: " + type(@rt) + " / local " + type(rt)
    -> (req)
      << "closure sees: " + type(rt)
      c = rt.klass.new(req)
      c.show

+ Table
  ro :rts

  -> new
    @rts = []

  -> add(rt)
    @rts.push(rt)

  -> run(req)
    found = @rts[0]
    << "run found: " + type(found)
    m = Mt.new(found)
    << "match rt: " + type(m.rt)
    h = m.handler
    h.call(req)

t = Table.new
t.add(Rt.new(Ctl))
<< t.run("one")
<< t.run("two")
