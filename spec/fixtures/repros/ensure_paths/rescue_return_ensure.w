# return from a RESCUE body: the exception frame is already consumed by the
# landing pad, but the ensure clause still guards the region — it must run
# before the return leaves the method.
+ R
  -> run
    @journal = ""
    begin
      raise "x"
    rescue e
      @journal = @journal + "R"
      return 5
    ensure
      @journal = @journal + "E"

  -> journal
    @journal

r = R.new
<< "result:" + r.run().to_s()
<< "order:" + r.journal()
