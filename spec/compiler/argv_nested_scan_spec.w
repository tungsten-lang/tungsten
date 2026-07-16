# Both argv spellings occur only inside nested method/block bodies. The
# lowering prepass must still give main argc/argv parameters and emit one
# argv_init before either method can execute.

-> nested_argv_call
  [0].map -> argv().size

-> nested_argv_constant
  [0].map -> ARGV.size

call_count = nested_argv_call()[0]
constant_count = nested_argv_constant()[0]
if call_count != constant_count
  << "FAIL nested argv scan: call=[call_count] constant=[constant_count]"
  exit(1)

<< "argv nested scan: ok"
