# Array#compact is source-defined. A value produced only at runtime must still
# pull in core/array.w without an Array literal, class reference, or explicit
# use declaration.

args = argv()
got = args.compact

if got.size != args.size
  << "FAIL Array#compact runtime-value autoload size=[got.size] expected=[args.size]"
  exit(1)
if wvalue_bits(got) == wvalue_bits(args)
  << "FAIL Array#compact runtime-value autoload returned receiver"
  exit(1)

<< "PASS Array#compact runtime-value autoload"
