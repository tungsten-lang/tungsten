# wasm32-wasi REPL entry: interpret ONE program and exit.
#
#   tungsten.wasm [path] [script args…]   interpret `path` (default /work/main.w)
#   tungsten.wasm - [script args…]        interpret the program read from stdin
#
# This is the `run --interpret` arm of compiler/tungsten_driver.w with the whole
# compile / link / CLI surface left out, so the image carries only the lexer,
# parser, tree-walking interpreter and the error formatter.
use ../compiler/lib/interpreter
use ../compiler/lib/error_formatter
use ../compiler/lib/hashing

# The rescue lives in a function, not at top level: a setjmp in `main` makes
# LLVM's wasm SjLj lowering rewrite every one of main's ~5k registration calls
# (a 21 MB function, past V8's 7.6 MB per-function limit).
-> wasm_repl_run(source, path, script_args)
  begin
    interp = Interpreter.new(script_args)
    interp.run(source, path)
  rescue err
    ccall("w_flush")
    if type(err) == "Hash" && err[:rt] == :compile_error
      ccall("w_eputs", emit_compile_error(err))
    elsif type(err) == "String"
      ccall("w_eputs", format_runtime_error(err, path))
    else
      ccall("w_eputs", format_runtime_error(err.to_s(), path))
    return 1
  0

# A wasm instance cannot spawn `uname`; name the target so `on <target>` guards
# in interpreted code resolve (compiler/lib/target.w#detect_target).
ccall("w_setenv", "TUNGSTEN_TARGET", "wasm32-wasip1")

args = argv()
path = "/work/main.w"
script_args = []
i = 0
while i < args.size()
  if i == 0
    path = args[i]
  else
    script_args.push(args[i])
  i += 1

# `-` reads the program from stdin. wasi_shim.js serves the request's stdin
# bytes as the file /dev/stdin, so one read path covers both spellings.
label = path
if path == "-"
  path = "/dev/stdin"
  label = "(stdin)"
source = read_file(path)
if source == nil
  ccall("w_eputs", "tungsten: cannot read " + label)
  exit 2

exit wasm_repl_run(source, label, script_args)
