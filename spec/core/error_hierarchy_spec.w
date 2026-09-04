# The error hierarchy: Exception is the abstract root, Error the base of
# every rescuable error, and the runtime's own failures surface as typed
# Error subclasses so `rescue e: Class` can select them.
#
# Run: `bin/tungsten -o /tmp/eh spec/core/error_hierarchy_spec.w && /tmp/eh`

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

# --- class relationships ---
check("no_method.is_name_error", NoMethodError.new("x").is_a?(NameError), "true")
check("no_method.is_error", NoMethodError.new("x").is_a?(Error), "true")
check("no_method.is_exception", NoMethodError.new("x").is_a?(Exception), "true")
check("file_not_found.is_io_error", FileNotFound.new("x").is_a?(IOError), "true")
check("timeout.is_network_error", TimeoutError.new("x").is_a?(NetworkError), "true")
check("tls.is_network_error", TLSError.new("x").is_a?(NetworkError), "true")
check("key_error.not_index_error", KeyError.new("x").is_a?(IndexError), "false")
check("system_exit.not_error", SystemExit.new("bye").is_a?(Error), "false")
check("system_exit.is_exception", SystemExit.new("bye").is_a?(Exception), "true")
check("argument_error.still_error", ArgumentError.new("x").is_a?(Error), "true")

# --- fields ---
e = ParseError.new("unexpected token")
check("message", e.message, "unexpected token")
check("to_s", e.to_s, "unexpected token")
check("code.default", e.code == nil, "true")
check("cause.default", e.cause == nil, "true")
check("data.default", e.data == nil, "true")
e.code = :E_PARSE_EXPECTED_TOKEN
e.data = {line: 3}
check("code.set", e.code, "E_PARSE_EXPECTED_TOKEN")
check("data.set", e.data[:line], "3")

inner = IOError.new("disk gone")
outer = AssertionError.new("save failed").with_cause(inner)
check("with_cause.returns_self", outer.is_a?(AssertionError), "true")
check("cause.message", outer.cause.message, "disk gone")
check("full_message.chain", outer.full_message, "AssertionError: save failed\n  caused by IOError: disk gone")
check("with_code", ZeroDivisionError.new("by zero").with_code(:E_DIV_ZERO).code, "E_DIV_ZERO")

# --- raise/rescue with the two-arg form and a typed clause ---
-> typed_catch
  begin
    raise KeyError, "no such key"
  rescue e: KeyError
    "caught " + e.class_name + ": " + e.message
check("raise.two_arg_typed", typed_catch(), "caught KeyError: no such key")

# --- runtime failures arrive as typed errors when the class is linked ---
-> divide(a, b)
  a / b
-> zero_division
  begin
    divide(10, 0)
  rescue e: ZeroDivisionError
    "zero division: " + e.message
check("runtime.zero_division", zero_division(), "zero division: division by zero")

-> no_method
  begin
    nil.definitely_missing
  rescue e: NoMethodError
    "no method: " + e.message.starts_with?("undefined method 'definitely_missing'").to_s
check("runtime.no_method", no_method(), "no method: true")

-> no_method_is_name_error
  begin
    nil.also_missing
  rescue e: NameError
    "name error family"
check("runtime.no_method_parent", no_method_is_name_error(), "name error family")

<< "error_hierarchy_spec: all checks passed"
