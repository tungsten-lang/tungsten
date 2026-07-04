require "tmpdir"

RSpec.describe "core filesystem APIs" do
  def run(code)
    Tungsten::Interpreter.new.run(code)
  end

  def with_tungsten_root(root)
    old_root = ENV["TUNGSTEN_ROOT"]
    ENV["TUNGSTEN_ROOT"] = root
    yield
  ensure
    ENV["TUNGSTEN_ROOT"] = old_root
  end

  it "writes through File.write block syntax and closes the handle" do
    Dir.mktmpdir("tungsten-file-write") do |dir|
      path = File.join(dir, "notes.txt")

      result = run(<<~W)
        handles = []
        File.write("#{path}") -> (file)
          handles.push(file)
          file.write("hello")
          file.write(" world")
        contents = File.read("#{path}")
        closed = handles.first.closed?
        contents == "hello world" && closed
      W

      expect(result).to eq(true)
    end
  end

  it "opens files with managed block syntax" do
    Dir.mktmpdir("tungsten-file-open") do |dir|
      path = File.join(dir, "open.txt")

      result = run(<<~W)
        File.open("#{path}", "w") -> (file)
          file.puts("one")
          file.write("two")
        File.read("#{path}")
      W

      expect(result).to eq("one\ntwo")
    end
  end

  it "exposes metadata on managed file handles" do
    Dir.mktmpdir("tungsten-file-handle-meta") do |dir|
      path = File.join(dir, "handle.txt")

      result = run(<<~W)
        File.write("#{path}", "abc")
        File.open("#{path}") -> (file)
          [file.size, file.type, file.mtime_ns != nil]
      W

      expect(result).to eq([ 3, "file", true ])
    end
  end

  it "lists and iterates directory filenames" do
    Dir.mktmpdir("tungsten-dir-ls") do |dir|
      File.write(File.join(dir, "alpha.txt"), "a")
      File.write(File.join(dir, "beta.txt"), "b")

      result = run(<<~W)
        names = Dir.ls("#{dir}")
        seen = []
        Dir.each("#{dir}") -> (name)
          seen.push(name)
        listed = names.includes?("alpha.txt")
        iterated = seen.includes?("beta.txt")
        [listed, iterated]
      W

      expect(result).to eq([ true, true ])
    end
  end

  it "exposes file metadata and symlink operations" do
    Dir.mktmpdir("tungsten-file-meta") do |dir|
      target = File.join(dir, "target.txt")
      link = File.join(dir, "target-link.txt")

      result = run(<<~W)
        File.write("#{target}", "abcde")
        File.symlink("#{target}", "#{link}")
        [
          File.exists?("#{target}"),
          File.file?("#{target}"),
          File.size("#{target}"),
          File.type("#{target}"),
          File.mtime_ns("#{target}") != nil,
          File.symlink?("#{link}"),
          File.type("#{link}"),
          File.readlink("#{link}") == "#{target}"
        ]
      W

      expect(result).to eq([ true, true, 5, "file", true, true, "symlink", true ])
    end
  end

  it "exposes path object filesystem metadata" do
    Dir.mktmpdir("tungsten-path-meta") do |dir|
      path = File.join(dir, "path.txt")
      File.write(path, "abc")

      result = run(<<~W)
        p = Path("#{path}")
        [p.file?, p.size, p.file_type, p.mtime_ns != nil]
      W

      expect(result).to eq([ true, 3, "file", true ])
    end
  end

  it "returns the project root as a Path" do
    result = run(<<~W)
      root = Tungsten.root
      root.type == "Path" && root.to_s == "#{PROJECT_ROOT}"
    W

    expect(result).to eq(true)
  end

  it "joins path segments" do
    Dir.mktmpdir("tungsten-path-join") do |dir|
      expected = File.join(dir, "nested", "leaf.txt")

      result = run(<<~W)
        joined = Path("#{dir}").join("nested", "leaf.txt")
        slash_joined = Path("#{dir}") / "nested"
        joined.to_s == "#{expected}" && slash_joined.name == "nested"
      W

      expect(result).to eq(true)
    end
  end

  it "enumerates directory paths from Path objects" do
    Dir.mktmpdir("tungsten-path-enumerable") do |dir|
      File.write(File.join(dir, "alpha.txt"), "a")
      File.write(File.join(dir, "beta.txt"), "b")

      result = run(<<~W)
        dir = Path("#{dir}")
        entries = dir.entries
        children = dir.children
        listed = dir.ls.map -> (child)
          child.name
        seen = []
        dir.each -> (child)
          seen.push(child.name)
        mapped = dir.map -> (child)
          child.name
        has_entry_name = entries.includes?("alpha.txt")
        has_child_path = children.first.type == "Path"
        has_listed_name = listed.includes?("beta.txt")
        has_seen_name = seen.includes?("alpha.txt")
        has_mapped_name = mapped.includes?("beta.txt")
        has_entry_name && has_child_path && has_listed_name && has_seen_name && has_mapped_name && !dir.empty?
      W

      expect(result).to eq(true)
    end
  end

  it "autoloads core filesystem classes for scripts outside the project root" do
    Dir.mktmpdir("tungsten-external-script") do |dir|
      script = File.join(dir, "main.w")
      path = File.join(dir, "external.txt")
      source = <<~W
        File.write("#{path}", "abc")
        Dir.entries("#{dir}").includes?("external.txt")
      W

      result = with_tungsten_root(PROJECT_ROOT) do
        Tungsten::Interpreter.new.run(source, file_path: script)
      end

      expect(result).to eq(true)
    end
  end
end
