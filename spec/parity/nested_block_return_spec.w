# Nested blocks return to their lexical method, even inside a user iterator.
# A method called from a block still owns its independent return target.

-> invoke(&)
  &()
  "iterator finished"

-> nested_return(found)
  [false, true].each -> (outer)
    invoke() ->
      [false, true].each -> (inner)
        if found && outer && inner
          begin
            return "found"
          rescue error
            raise "return entered rescue"
  "missing"

-> nested_nil
  invoke() ->
    invoke() ->
      return nil
  "unreachable"

-> own_return
  [1].each -> (value)
    return value + 1
  0

-> separate_method
  [1].each -> (value)
    [1].each -> (other)
      result = own_return()
      if result != 2
        raise "called method lost its return"
  "outer finished"

-> nested_ensure(log)
  invoke() ->
    invoke() ->
      begin
        return "ensured"
      ensure
        log.push("cleanup")
  "unreachable"

if nested_return(true) != "found" || nested_return(false) != "missing"
  raise "nested return lost its lexical target"
if nested_nil() != nil || separate_method() != "outer finished"
  raise "nested return crossed the wrong method"
log = []
if nested_ensure(log) != "ensured" || log != ["cleanup"]
  raise "nested return skipped ensure"
<< "nested block returns passed"
