# File.file?, File.symlink? and File.type (core/file.w), interpreted and native.
#
# Run:
#   bin/tungsten run --interpret spec/core/file_predicates_spec.w
#   bin/tungsten -o /tmp/file_predicates_spec spec/core/file_predicates_spec.w && /tmp/file_predicates_spec

use core/file

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

tempfile = Tempfile.new("tungsten-file-predicates")
path = tempfile.path
check("write", tempfile.write("w") == 1)
check("file? on a regular file", File.file?(path))
check("file? on a directory", !File.file?(File.expand_path("spec")))
check("file? on a missing path", !File.file?(path + ".missing"))
check("symlink? on a regular file", !File.symlink?(path))
check("type of a regular file", File.type(path) == "file")
check("type of a directory", File.type(File.expand_path("spec")) == "directory")
check("type of a missing path", File.type(path + ".missing") == nil)
check("file_type alias", File.file_type(path) == "file")
<< "file_predicates_spec: all checks passed"
