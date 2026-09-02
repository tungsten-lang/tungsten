# Bounded prefix reads used by SciIO format detection.

use core/io

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

tmp = Tempfile.new("tungsten-sciio-prefix")
path = tmp.path
tmp.close()

begin
  File.write(path, "PAR1payload")
  check("zero prefix", File.read_prefix(path, 0) == "")
  check("missing zero prefix", File.read_prefix(path + ".missing", 0) == nil)
  check("directory zero prefix", File.read_prefix(".", 0) == nil)
  check("bounded prefix", File.read_prefix(path, 4) == "PAR1")
  check("short file", File.read_prefix(path, 100) == "PAR1payload")
  check("missing file", File.read_prefix(path + ".missing", 4) == nil)
  check("SciIO delegates bounded read", SciIO.read_prefix(path, 4) == "PAR1")
  check("SciIO magic sniff", SciIO.sniff(path)[:format] == :parquet)
  check("Parquet metadata probe", SciIO.read_parquet(path)[:format] == :parquet)

  File.write(path, "MATLAB 5.0 MAT-file, bounded metadata")
  mat = SciIO.read_mat(path)
  check("MAT metadata probe", mat[:format] == :mat && mat[:level] == 5)
  check("MAT bounded description", mat[:description].size() <= 116)

  raised = false
  begin
    File.read_prefix(path, 0 - 1)
  rescue error
    raised = true
  check("negative length raises", raised)
ensure
  File.unlink(path) if File.exist?(path)

<< "sci_io_prefix_spec: all checks passed"
