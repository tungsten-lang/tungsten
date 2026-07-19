# Nested ensures: a return from the inner try body runs BOTH ensure bodies,
# innermost first, then returns the value computed before either ran.
+ Nest
  -> run
    @journal = ""
    begin
      begin
        @journal = @journal + "T"
        return 7
      ensure
        @journal = @journal + "I"
    ensure
      @journal = @journal + "O"

  -> journal
    @journal

n = Nest.new
<< "result:" + n.run().to_s()
<< "order:" + n.journal()
