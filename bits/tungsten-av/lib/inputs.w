in Av

+ Inputs
  -> .implementation(toolchain, package)
    paths = [toolchain + "/bin/tungsten", toolchain + "/bin/tungsten-compiler"]
    ["runtime", "core", "compiler", "apps/studio", "bits/tungsten-av", "bits/tungsten-bit"].each ->(tree)
      File.walk(toolchain + "/" + tree, ->(path)
        paths.push(path) if File.file?(path) && [".w", ".c", ".m", ".h"].include?(File.extname(path))
      )
    File.walk(package, ->(path)
      paths.push(path) if File.file?(path) && [".w", ".c", ".m", ".h"].include?(File.extname(path))
    )
    files = {}
    Util.unique(paths).each ->(path)
      key = path.starts_with?(toolchain + "/") ? path.slice(toolchain.size + 1, path.size) : "package/" + path.slice(package.size + 1, path.size)
      files[key] = Util.sha(path)
    {"sha256": Crypto.sha256(JSON.encode(files)), "files": files, "runtime": ccall("w_media_runtime_identity")}

+ Snapshots
  -> new(@directory, @reserve = 0)

  -> seal(source)
    source = File.realpath(source)
    before = Util.stamp(source)
    digest = Util.sha(source)
    raise "input changed while hashing: [source]" if before != Util.stamp(source)
    File.mkdir_p(@directory)
    destination = @directory + "/" + digest + File.extname(source).downcase
    lock = Util.lock(@directory + "/" + digest + ".lock")
    temporary = @directory + "/." + digest + "-" + Util.id()
    method = "reused"
    begin
      if File.exist?(destination)
        raise "sealed input is corrupt: [destination]" if Util.sha(destination) != digest
      else
        free = ccall("w_av_free", @directory)
        raise "insufficient disk for input snapshot and reserve" if free < before[2] + @reserve
        method = Util.copy_file(source, temporary)
        raise "input changed during snapshot: [source]" if before != Util.stamp(source) || Util.sha(temporary) != digest
        File.chmod(temporary, 0o444)
        Util.sync(temporary)
        File.atomic_replace(temporary, destination)
      raise "input changed while opening snapshot" if before != Util.stamp(source)
    ensure
      Util.unlink(temporary)
      Util.unlock(lock)
    {"source": source, "path": destination, "sha256": digest, "bytes": before[2], "method": method}

  -> local_uses(path, text)
    result = []
    text.split("\n").each ->(line)
      stripped = line.strip
      if stripped.starts_with?("use ")
        reference = stripped.slice(4, stripped.size).strip
        if reference.starts_with?("\"") || reference.starts_with?("'")
          name = Tungsten:Bit:Bitfile.literal_arguments(reference)[0][0]
        else
          name = reference.split(" ")[0]
        target = Util.absolute(name, File.dirname(path))
        target += ".w" if !target.ends_with?(".w")
        result.push([line, File.realpath(target)]) if File.file?(target)
    result

  -> tree(paths, root, directory)
    root = File.realpath(root)
    pending = paths.dup
    files = {}
    directories = {}
    while pending.size > 0
      path = Util.canonical(Util.absolute(pending.pop))
      if File.directory?(path)
        if !directories.has_key?(path)
          directories[path] = true
          File.children(path).each ->(name)
            pending.push(path + "/" + name) if ![".git", ".av", "__pycache__"].include?(name)
      elsif !files.has_key?(path)
        raise "declared input is missing: [path]" if !File.file?(path)
        files[path] = seal(path)
        if File.extname(path) == ".w"
          local_uses(path, File.read(files[path]["path"])).each ->(item)
            pending.push(item[1])
    identity = {}
    files.keys.sort.each ->(path)
      identity[path] = files[path]["sha256"]
    destination = directory + "/" + Crypto.sha256(JSON.encode(identity))
    mapping = {}
    files.keys.sort.each ->(path)
      relative = Util.inside?(path, root) ? path.slice(root.size + 1, path.size) : ".external/" + Crypto.sha256(File.dirname(path)).slice(0, 16) + "/" + File.basename(path)
      mapping[path] = destination + "/" + relative
    records = []
    files.keys.sort.each ->(path)
      sealed = files[path]
      target = mapping[path]
      expected = sealed["sha256"]
      data = nil
      if File.extname(path) == ".w"
        original = File.read(sealed["path"])
        data = original
        local_uses(path, original).each ->(item)
          replacement = mapping[item[1]]
          data = data.replace(item[0], "use \"" + replacement.slice(0, replacement.size - 2) + "\"") if replacement != nil
        expected = Crypto.sha256(data)
      if File.exist?(target)
        raise "frozen input tree is corrupt: [target]" if Util.sha(target) != expected
      else
        File.mkdir_p(File.dirname(target))
        tmp = target + ".part-" + Util.id()
        begin
          if data != nil
            File.write(tmp, data)
          else
            Util.copy_file(sealed["path"], tmp)
          File.chmod(tmp, 0o444)
          Util.sync(tmp)
          File.atomic_replace(tmp, target)
        ensure
          Util.unlink(tmp)
      records.push(sealed.merge({"frozen": target, "frozen_sha256": expected}))
    {"records": records, "mapping": mapping, "root": destination}
