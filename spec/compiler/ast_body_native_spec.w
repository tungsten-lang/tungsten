# Packed AST child lists dispatch through the native Tungsten Body class after
# the runtime 0xE6 IC table is removed.

use ../../core/ast_body

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

-> check_array(name, got, expected)
  check(name + " size", got.size, expected.size)
  i = 0
  while i < expected.size
    check(name + " item " + i.to_s, got[i], expected[i])
    i += 1

-> body(values)
  ccall_nobox("w_ast_freeze_if_array", values)

empty = body([])
values = body([nil, false, true, -2, 0, 3, 8])

# Body's private dispatch identity must not leak through public
# introspection. Compiler passes intentionally accept packed child lists
# anywhere they accept Arrays; only method dispatch distinguishes Body.
check("public type", type(values), "Array")
check("public class_name", values.class_name, "Array")
check("public class", values.class, Array)
check("is_a Array", values.is_a?(Array), true)
check("is_a Body", values.is_a?(Tungsten:AST:Body), false)
check("is_a Array name", values.is_a?("Array"), true)
check("is_a Body name", values.is_a?("Tungsten:AST:Body"), false)

fields = ccall("w_value_fields", values)
check("inspector names body subtype", fields.include?("body"), true)

check("empty size", empty.size, 0)
check("empty empty?", empty.empty?, true)
check("empty read", empty.read(0), nil)
check("size", values.size, 7)
check("empty?", values.empty?, false)

indexes = [-9, -8, -7, -2, -1, 0, 1, 6, 7, 9]
expected = [nil, nil, nil, 3, 8, nil, false, 8, nil, nil]
i = 0
while i < indexes.size
  check("read " + indexes[i].to_s, values.read(indexes[i]), expected[i])
  check("index " + indexes[i].to_s, values[indexes[i]], expected[i])
  i += 1

seen = []
returned = values.each -> (item)
  seen.push(item)
check_array("each", seen, [nil, false, true, -2, 0, 3, 8])
check("each returns self", returned, values)

check_array("map", values.map -> (item) item == nil ? 99 : item,
            [99, false, true, -2, 0, 3, 8])
check_array("select", values.select -> (item) item != nil && item != false,
            [true, -2, 0, 3, 8])
check_array("reject", values.reject -> (item) item != nil && item != false,
            [nil, false])
check("find", values.find -> (item) item == 3, 3)
check("any no block", values.any?, true)
check("all no block", values.all?, false)
check("none no block", values.none?, false)
check("empty any", empty.any?, false)
check("empty all", empty.all?, true)
check("empty none", empty.none?, true)
check("any block", values.any? -> (item) item == 8, true)
check("all block", values.all? -> (item) item == nil || item == false || item == true || item <= 8, true)
check("none block", values.none? -> (item) item == 100, true)
check("reduce", values.compact.reduce(0) -> (acc, item) item == false || item == true ? acc : acc + item, 9)
check_array("compact", values.compact, [false, true, -2, 0, 3, 8])
check_array("dup", values.dup, [nil, false, true, -2, 0, 3, 8])
check_array("to_a", values.to_a, [nil, false, true, -2, 0, 3, 8])

check("immutable", values.respond_to?("[]="), false)

<< "ast_body_native_spec: all checks passed"
