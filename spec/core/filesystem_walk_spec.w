use core/file
use core/directory
use core/dir

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

root = "spec/fixtures/filesystem_walk"
check("file.join.interpreter_parity", File.join(root, "nested") == root + "/nested")
check("file.join.multiple", File.join(root, "nested", "child.txt") == root + "/nested/child.txt")
check("file.join.empty", File.join() == "")
check("file.read_dir.no_recursion", File.read_dir(root).sort() == ["nested", "root.txt"])
expected = [
  root,
  root + "/nested",
  root + "/nested/child.txt",
  root + "/root.txt"
]

file_paths = []
file_collector = -> (path) file_paths.push(path)
returned = File.walk(root, file_collector)
check("file.walk.paths", file_paths.sort() == expected)
check("file.walk.return", returned == root)

directory_paths = []
directory_collector = -> (path) directory_paths.push(path)
Directory.walk(root, directory_collector)
check("directory.walk", directory_paths.sort() == expected)

dir_paths = []
dir_collector = -> (path) dir_paths.push(path)
Dir.walk(root, dir_collector)
check("dir.walk", dir_paths.sort() == expected)

file_path = root + "/root.txt"
single = []
single_collector = -> (path) single.push(path)
File.walk(file_path, single_collector)
check("file.walk.file", single == [file_path])

missing = root + "/missing"
missing_paths = []
missing_collector = -> (path) missing_paths.push(path)
File.walk(missing, missing_collector)
check("file.walk.missing", missing_paths == [missing])

<< "filesystem_walk_spec: all checks passed"
