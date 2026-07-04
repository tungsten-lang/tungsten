# # Global
#
# The Global module is included by the class Object, so its methods are available
# in every Tungsten object.
#
# The Global instance methods are documented in class Object while the
# module methods are documented here. These methods are called without a receiver and thus
# can be called in functional form:
#
#     sprintf "%.2f%", 0.25 * 100 #=> "25.00%"
in Global

-> __callee__
-> __dir__
-> __method__

-> ``/1 (str)

-> abort

# Register a zero-argument function or block to be called when the process exits.
-> at_exit(f)
-> at_exit(&b)

-> autoload(module, filename)
-> autoload?

-> binding
-> block_given?

-> caller
-> caller_locations

-> eval(string)
-> eval(string, binding)
-> eval(string, binding, filename, lineno)

# Replaces the current process by running the _command_.
-> exec(comamnd)

# Exit the process, after running at_exit hooks
-> exit(status = 0)

# Exit the process immediately, without running at_exit hooks
-> exit!(status = 1)

-> fail(msg = nil, code = 1)
  STDERR << msg if msg
  exit code

-> fork
-> format

-> gets --> STDIN

-> globals
-> gsub(pattern, replacement)
-> gsub(pattern)

-> lambda

-> load(filename, safe: false)
-> locals

-> loop
  yield while true

-> open(path)
-> open(path, mode = nil, perm = nil, opt = nil)

-> p/1
-> p(*args)
  args.each &.p
  args

-> print(*args)

-> puts --> STDOUT

-> raise
-> raise/1 (str)
-> raise(exception, string = nil, array = nil)
-> readline
-> readlines
-> require(name)
-> require_relative(name)

-> select
-> sleep(duration = nil)
-> spawn
-> sprintf(format, *args)
-> syscall(num, *args)
-> system(command)

-> test(cmd, file)
-> to_s
  "#<[class]:0x[__id__.to_s(16)]>"

-> trap(signal, command)
-> trap(signal)

-> warn(msg)
