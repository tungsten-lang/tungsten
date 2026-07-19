# raise during a return-unwind: the ensure body itself raises while a
# `return` is in flight. The raise wins over the pending return and must
# propagate to handlers OUTSIDE the begin (never the begin's own rescue),
# so the caller's rescue catches it and the return value is abandoned.
+ Boom
  -> risky
    begin
      return 1
    ensure
      raise "from-ensure"

b = Boom.new
begin
  r = b.risky()
  << "no-raise:" + r.to_s()
rescue e
  << "caught:" + e.to_s()
