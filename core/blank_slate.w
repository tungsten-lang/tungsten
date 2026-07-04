# # BlankSlate
#
# BlankSlate is the parent class of all classes in Tungsten. It's an explicit blank class.
+ BlankSlate
  -> new

  -> !/1 false

  -> !=/1
  -> ==/1

  -> instance_eval(string, filename = nil, line_number = nil)
  -> instance_eval

  -> instance_exec(*args)

  -> send(symbol, *args)
  alias :__send__, :send

  private

  -> method_missing(symbol, *args)

  -> singleton_added/1
  -> singleton_removed/1
  -> singleton_undefined/1
