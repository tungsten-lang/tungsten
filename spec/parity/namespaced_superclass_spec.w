# Fully qualified superclass names must parse and dispatch on every engine.
+ CommandBase:Native:Command
  -> value
    23

+ CommandChild < CommandBase:Native:Command
  -> execute
    value + 19

<< CommandChild.new.execute
<< CommandChild.new.is_a?(CommandBase:Native:Command)
