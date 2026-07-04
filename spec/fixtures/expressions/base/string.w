ex %["foo"], "foo"
ex %[name = "world"; "hello [name]"], "hello world"

ex %[name = nil;     "hello[ name]"], "hello"
ex %[name = "world"; "hello[ name]"], "hello world"
