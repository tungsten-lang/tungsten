# return INSIDE an ensure body while another return is in flight: the
# ensure's own return wins (it overrides the pending transfer, matching
# the interpreter's pending-error shape and Ruby semantics).
+ P
  -> run
    begin
      return 1
    ensure
      return 2

<< "got:" + P.new.run().to_s()
