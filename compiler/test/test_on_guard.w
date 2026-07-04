use assert
use ../lib/ast
use ../lib/lexer
use ../lib/parser
use ../lib/target

-> parse(source)
  lexer = Lexer.new(source, "(test)")
  token_count = lexer.tokenize()
  Parser.new(token_count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars).parse()

-> first_expr(source)
  ast = parse(source)
  ast[:expressions][0]

# -- Parser tests --

test "parses simple 'on macos' block"
node = first_expr("on macos\n  -> clock_ms\n    42")
assert_eq node[:node], :on_guard
assert_eq node[:predicate][:node], :target_designator
assert_eq node[:predicate][:name], "macos"
assert_eq node[:capabilities].size(), 0
assert_eq node[:body].size(), 1

test "parses 'on linux && x86_64'"
node = first_expr("on linux && x86_64\n  -> clock_ms\n    42")
assert_eq node[:predicate][:node], :target_and
assert_eq node[:predicate][:left][:name], "linux"
assert_eq node[:predicate][:right][:name], "x86_64"

test "parses 'on linux || macos'"
node = first_expr("on linux || macos\n  -> clock_ms\n    42")
assert_eq node[:predicate][:node], :target_or
assert_eq node[:predicate][:left][:name], "linux"
assert_eq node[:predicate][:right][:name], "macos"

test "parses 'on linux with io_uring'"
node = first_expr("on linux with io_uring\n  -> submit\n    42")
assert_eq node[:predicate][:node], :target_designator
assert_eq node[:predicate][:name], "linux"
assert_eq node[:capabilities].size(), 1
assert_eq node[:capabilities][0], "io_uring"

test "parses 'on linux && x86_64 with io_uring'"
node = first_expr("on linux && x86_64 with io_uring\n  -> submit\n    42")
assert_eq node[:predicate][:node], :target_and
assert_eq node[:predicate][:left][:name], "linux"
assert_eq node[:predicate][:right][:name], "x86_64"
assert_eq node[:capabilities][0], "io_uring"

test "parses 'on !(linux || macos)'"
node = first_expr("on !(linux || macos)\n  -> clock_ms\n    42")
assert_eq node[:predicate][:node], :target_not
assert_eq node[:predicate][:expression][:node], :target_or
assert_eq node[:predicate][:expression][:left][:name], "linux"
assert_eq node[:predicate][:expression][:right][:name], "macos"

test "parses grouped expression 'on linux && (x86_64 || arm64)'"
node = first_expr("on linux && (x86_64 || arm64)\n  -> clock_ms\n    42")
assert_eq node[:predicate][:node], :target_and
assert_eq node[:predicate][:left][:name], "linux"
assert_eq node[:predicate][:right][:node], :target_or
assert_eq node[:predicate][:right][:left][:name], "x86_64"
assert_eq node[:predicate][:right][:right][:name], "arm64"

test "gives 'with' the lowest precedence"
node = first_expr("on linux || macos with kqueue\n  -> poll\n    42")
assert_eq node[:predicate][:node], :target_or
assert_eq node[:capabilities][0], "kqueue"

test "supports chained 'with' clauses"
node = first_expr("on linux with io_uring with fast_clock\n  -> submit\n    42")
assert_eq node[:capabilities].size(), 2
assert_eq node[:capabilities][0], "io_uring"
assert_eq node[:capabilities][1], "fast_clock"

test "parses multiple definitions inside an on block"
src = "on macos\n  -> clock_ms\n    42\n  -> monotonic_ns\n    99"
node = first_expr(src)
assert_eq node[:body].size(), 2

# -- Target matching tests --

test "normalize_designator maps amd64 to x86_64"
assert_eq normalize_designator("amd64"), "x86_64"

test "normalize_designator maps intel to x86_64"
assert_eq normalize_designator("intel"), "x86_64"

test "normalize_designator maps aarch64 to arm64"
assert_eq normalize_designator("aarch64"), "arm64"

test "normalize_designator passes through known names"
assert_eq normalize_designator("macos"), "macos"
assert_eq normalize_designator("linux"), "linux"
assert_eq normalize_designator("x86_64"), "x86_64"

test "evaluate_target_predicate matches os"
target = {os: "macos", arch: "x86_64", features: []}
pred = ast_target_designator("macos")
assert_true evaluate_target_predicate(pred, target)

test "evaluate_target_predicate rejects non-matching os"
target = {os: "linux", arch: "x86_64", features: []}
pred = ast_target_designator("macos")
assert_false evaluate_target_predicate(pred, target)

test "evaluate_target_predicate matches arch"
target = {os: "macos", arch: "x86_64", features: []}
pred = ast_target_designator("x86_64")
assert_true evaluate_target_predicate(pred, target)

test "evaluate_target_predicate normalizes aliases"
target = {os: "macos", arch: "x86_64", features: []}
pred = ast_target_designator("amd64")
assert_true evaluate_target_predicate(pred, target)

test "evaluate_target_predicate AND"
target = {os: "linux", arch: "x86_64", features: []}
pred = ast_target_and(ast_target_designator("linux"), ast_target_designator("x86_64"))
assert_true evaluate_target_predicate(pred, target)

test "evaluate_target_predicate AND rejects partial"
target = {os: "linux", arch: "arm64", features: []}
pred = ast_target_and(ast_target_designator("linux"), ast_target_designator("x86_64"))
assert_false evaluate_target_predicate(pred, target)

test "evaluate_target_predicate OR"
target = {os: "macos", arch: "x86_64", features: []}
pred = ast_target_or(ast_target_designator("linux"), ast_target_designator("macos"))
assert_true evaluate_target_predicate(pred, target)

test "evaluate_target_predicate NOT"
target = {os: "macos", arch: "x86_64", features: []}
pred = ast_target_not(ast_target_designator("linux"))
assert_true evaluate_target_predicate(pred, target)

test "target_matches? checks capabilities"
target = {os: "linux", arch: "x86_64", features: ["io_uring"]}
pred = ast_target_designator("linux")
assert_true target_matches?(pred, ["io_uring"], target)

test "target_matches? rejects missing capability"
target = {os: "linux", arch: "x86_64", features: []}
pred = ast_target_designator("linux")
assert_false target_matches?(pred, ["io_uring"], target)

test "expand_on_guards inlines matching guards"
target = {os: "macos", arch: "x86_64", features: []}
body = [
  ast_on_guard(ast_target_designator("macos"), [], [ast_method_def("tick", [], [ast_int(42)])]),
  ast_on_guard(ast_target_designator("linux"), [], [ast_method_def("tick", [], [ast_int(99)])])
]
result = expand_on_guards(body, target)
assert_eq result.size(), 1
assert_eq result[0][:name], "tick"
assert_eq result[0][:body][0][:value], 42

test "expand_on_guards drops overridden fallback"
target = {os: "macos", arch: "x86_64", features: []}
body = [
  ast_method_def("tick", [], [ast_int(0)]),
  ast_on_guard(ast_target_designator("macos"), [], [ast_method_def("tick", [], [ast_int(42)])])
]
result = expand_on_guards(body, target)
assert_eq result.size(), 1
assert_eq result[0][:body][0][:value], 42

test "expand_on_guards keeps fallback when no guard matches"
target = {os: "macos", arch: "x86_64", features: []}
body = [
  ast_method_def("tick", [], [ast_int(0)]),
  ast_on_guard(ast_target_designator("linux"), [], [ast_method_def("tick", [], [ast_int(99)])])
]
result = expand_on_guards(body, target)
assert_eq result.size(), 1
assert_eq result[0][:body][0][:value], 0

report
