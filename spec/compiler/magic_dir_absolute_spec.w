# Native `__DIR__` must remain a usable deployment anchor when this source is
# passed to the compiler by a relative path and the resulting binary is run
# from another working directory.

dir = __DIR__
if !dir.starts_with?("/")
  << "FAIL __DIR__ is relative: " + dir
  exit(1)
if read_file(dir + "/magic_dir_absolute_spec.w") == nil
  << "FAIL __DIR__ does not identify the source directory: " + dir
  exit(1)

<< "PASS absolute __DIR__ " + dir
