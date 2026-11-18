# Dir / Directory — class-method facade over the directory intrinsics (core/dir.w).
#
# Run from the repository root (it lists core/traits and spec/fixtures).

use core/dir

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# core/traits holds exactly these seven files.
traits = ["bit_equal.w", "bit_ordered.w", "comparable.w", "debuggable.w",
          "enumerable.w", "inspectable.w", "printable.w"]

# ---- listing: entries / children / read / ls are all read_dir ----
check("Dir.entries matches Directory.entries", Dir.entries("core/traits").sort == traits)
check("entries lists a directory", Directory.entries("core/traits").sort == traits)
check("entries default is the cwd", Directory.entries.include?("core"))
check("entries omits dot and dotdot",
      !Directory.entries("core/traits").include?(".") && !Directory.entries("core/traits").include?(".."))
check("entries of a missing directory is nil", Directory.entries("no/such/dir") == nil)
check("children is entries", Directory.children("core/traits").sort == traits)
check("read is entries", Directory.read("core/traits").sort == traits)
check("ls is entries", Directory.ls("core/traits").sort == traits)
check("entries returns a fresh array", Directory.entries("core/traits") != Directory.entries("core"))

# ---- predicates ----
check("exist? on a directory", Directory.exist?("core"))
check("exist? on a plain file is false", !Directory.exist?("VERSION"))
check("exist? on a missing path is false", !Directory.exist?("no/such/dir"))
check("exists? alias", Directory.exists?("core") && !Directory.exists?("VERSION"))
check("directory? alias", Directory.directory?("core") && !Directory.directory?("VERSION"))
check("empty? on a populated directory", !Directory.empty?("core/traits"))

# ---- iteration: each / foreach / each_child all yield entry names ----
each_seen = []
Directory.each("core/traits") -> (entry)
  each_seen.push(entry)
check("each yields every entry", each_seen.sort == traits)

foreach_seen = []
Directory.foreach("core/traits") -> (entry)
  foreach_seen.push(entry)
check("foreach is each", foreach_seen.sort == traits)

each_child_seen = []
Directory.each_child("core/traits") -> (entry)
  each_child_seen.push(entry)
check("each_child is each", each_child_seen.sort == traits)

check("each yields plain names, not paths", each_seen.include?("comparable.w"))

# ---- walk: recursive, takes an explicit visitor argument ----
walk_root = "spec/fixtures/filesystem_walk"
walked = []
Directory.walk(walk_root, -> (path) walked.push(path))
check("walk descends recursively",
      walked.sort == [walk_root, walk_root + "/nested", walk_root + "/nested/child.txt", walk_root + "/root.txt"])
check("walk yields the root itself", walked.include?(walk_root))

# ---- directory creation and working directory ----
cwd = Directory.pwd
check("pwd is a string", type(cwd) == "String")
check("pwd is absolute", cwd.slice(0, 1) == "/")
check("current is pwd", Directory.current == cwd)

temp = Tempfile.new("tungsten_directory_spec")
scratch = temp.path
temp.close!()
check("mkdir creates a directory", Directory.mkdir(scratch) == true && Directory.exist?(scratch))
check("a fresh directory is empty", Directory.empty?(scratch))
check("mkdir_p creates intermediate levels",
      Directory.mkdir_p(scratch + "/a/b/c") == true && Directory.exist?(scratch + "/a/b/c"))
check("parent of a nested tree is no longer empty", !Directory.empty?(scratch))
check("entries sees the new child", Directory.entries(scratch) == ["a"])

# chdir without a block moves the process; with a block it restores the old cwd.
Directory.chdir(scratch)
check("chdir moves the working directory", Directory.pwd.include?("tungsten_directory_spec"))
Directory.chdir(cwd)
check("chdir back", Directory.pwd == cwd)

block_saw = Directory.chdir(scratch) -> ()
  Directory.pwd
check("chdir with a block returns the block value", block_saw.include?("tungsten_directory_spec"))
check("chdir with a block restores the cwd", Directory.pwd == cwd)

cd_saw = Directory.cd(scratch) -> ()
  Directory.pwd
check("cd is chdir", cd_saw.include?("tungsten_directory_spec") && Directory.pwd == cwd)

check("rmdir removes an empty directory",
      Directory.rmdir(scratch + "/a/b/c") == true && !Directory.exist?(scratch + "/a/b/c"))
Directory.rmdir(scratch + "/a/b")
Directory.rmdir(scratch + "/a")
Directory.rmdir(scratch)
check("cleanup removed the scratch tree", !Directory.exist?(scratch))

<< "ALL PASS directory_spec ([passed.load()] checks)"
