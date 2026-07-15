# Array#join is source-defined, so values produced only at runtime must still
# pull in core/array.w even when the program contains no Array literal or Array
# class reference. The result bytes depend on the process arguments; merely
# reaching a String proves method registration and dispatch succeeded.

args = argv()
got = args.join("|")
if got.class_name != "String"
  << "FAIL Array#join runtime-value autoload class=[got.class_name]"
  exit(1)

<< "PASS Array#join runtime-value autoload"
