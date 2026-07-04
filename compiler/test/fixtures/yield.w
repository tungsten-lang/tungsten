-> greet(name)
  << "before"
  yield name
  << "after"

greet("world") -> (x)
  << "hello " + x
