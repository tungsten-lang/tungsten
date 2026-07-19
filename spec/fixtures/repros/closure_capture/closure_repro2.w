+ Ctl
  ro :req

  -> new(@req)

  -> act(a)
    a.call(self)

  -> show
    "shown:" + @req

+ Rt
  ro :klass
  ro :action

  -> new(@klass, @action)

+ Mt
  ro :rt

  -> new(@rt)

  -> handler
    rt = @rt
    -> (req)
      c = rt.klass.new(req)
      c.act(rt.action)

+ Table
  ro :rts

  -> new
    @rts = []

  -> add(rt)
    @rts.push(rt)

  -> run(req)
    found = nil
    @rts.each -> (r)
      if found == nil
        found = r
    m = Mt.new(found)
    h = m.handler
    h.call(req)

t = Table.new
t.add(Rt.new(Ctl, -> (c) c.show))
<< t.run("one")
<< t.run("two")
<< t.run("three")
