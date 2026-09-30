# The compiled walker used by the metaflip adapters: built once per source
# state into the experiment directory, keyed by a digest of its sources and
# of the compiler that produced it.
use core/file
use core/crypto/sha256
use proc

+ WalkerBuild
  # The `use` targets of a source file that live in the same tree.
  -> .imports(path)
    dir = Paths.dirname(path)
    found = []
    text = read_file(path)
    raise "cannot read " + path if text == nil
    text.split("\n").each -> (line)
      if line.starts_with?("use ") && !line.starts_with?("use core/")
        found.push(File.expand_path(dir + "/" + line.slice(4, line.size - 4).strip + ".w"))
    found

  # The source files a build of `entry` reads, in a fixed order.
  -> .sources(entry)
    seen = [File.expand_path(entry)]
    i = 0 ## i64
    while i < seen.size
      WalkerBuild.imports(seen[i]).each -> (path)
        seen.push(path) if !seen.include?(path)
      i += 1
    seen.sort

  # SHA-256 over the compiler identity and the contents of the sources.
  -> .digest(compiler, sources)
    body = "metabench-walker-v1\n" + compiler + "\n"
    sources.each -> (path)
      body = body + Paths.basename(path) + "\n" + read_file(path) + "\n"
    Crypto:SHA256.hexdigest(body)

  # A path, its size and its modification time: the identity of the compiler binary.
  -> .compiler_tag(compiler)
    "compiler:" + compiler + ":" + File.size(compiler).to_s + ":" + File.mtime_ns(compiler).to_s

  # Path of a walker binary that is fresh for the current sources; builds it when needed.
  -> .ensure(bit_root, experiment_dir, compiler)
    out_dir = File.expand_path(experiment_dir)
    entry = bit_root + "/tools/wide_rect_walk.w"
    binary = out_dir + "/bin/wide_rect_walk"
    stamp = binary + ".inputs"
    digest = WalkerBuild.digest(WalkerBuild.compiler_tag(compiler), WalkerBuild.sources(entry))
    recorded = read_file(stamp)
    if File.exists?(binary) && recorded != nil && recorded.strip == digest
      return binary
    File.mkdir_p(out_dir + "/bin")
    bits = Paths.dirname(bit_root)
    command = "cd " + Shell.quote(bit_root) + " && BIT_HOME=" + Shell.quote(bits) + " " + Shell.quote(compiler) + " -o " + Shell.quote(binary) + " tools/wide_rect_walk.w --release > " + Shell.quote(out_dir + "/bin/build.log") + " 2>&1"
    child = Child.spawn(["/bin/sh", "-c", command])
    done = child.wait(nil)[0]
    raise "walker build failed, see " + out_dir + "/bin/build.log" if !done.ok? || !File.exists?(binary)
    write_file(stamp, digest + "\n")
    binary
