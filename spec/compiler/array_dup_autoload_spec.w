# Array#dup is source-defined. A value produced only at runtime must still pull
# in core/array.w without an Array literal, class reference, or explicit use
# declaration.

args = argv()
got = args.dup

if got.size != args.size
  << "FAIL Array#dup runtime-value autoload size=[got.size] expected=[args.size]"
  exit(1)
if wvalue_bits(got) == wvalue_bits(args)
  << "FAIL Array#dup runtime-value autoload returned receiver"
  exit(1)

<< "PASS Array#dup runtime-value autoload"
