use assert
use ../lib/environment

test "define and get"
env = Environment.new()
env.define("x", 42)
assert_eq env.get("x"), 42

test "set updates existing"
env = Environment.new()
env.define("x", 1)
env.set("x", 2)
assert_eq env.get("x"), 2

test "set creates new if not defined"
env = Environment.new()
env.set("x", 99)
assert_eq env.get("x"), 99

test "defined? returns true for defined vars"
env = Environment.new()
env.define("x", 1)
assert_true env.defined?("x")
assert_false env.defined?("y")

test "parent scope lookup"
parent = Environment.new()
parent.define("x", 10)
child = Environment.new(parent)
assert_eq child.get("x"), 10

test "child shadows parent"
parent = Environment.new()
parent.define("x", 10)
child = Environment.new(parent)
child.define("x", 20)
assert_eq child.get("x"), 20
assert_eq parent.get("x"), 10

test "set walks up to parent"
parent = Environment.new()
parent.define("x", 10)
child = Environment.new(parent)
child.set("x", 20)
assert_eq parent.get("x"), 20

test "defined_locally?"
parent = Environment.new()
parent.define("x", 10)
child = Environment.new(parent)
assert_false child.defined_locally?("x")
child.define("y", 20)
assert_true child.defined_locally?("y")

report()
