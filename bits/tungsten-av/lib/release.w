in Av

+ Publisher
  -> new(@directory, @verify)
    @directory = Util.canonical(Util.absolute(@directory))

  -> publish(entries, provenance)
    raise "release requires at least one file" if entries.size == 0
    entries = entries.map ->(e) e.dup
    destinations = []
    pins = {}
    entries.each ->(entry)
      entry["destination"] = File.join(Util.canonical(File.dirname(entry["destination"])), File.basename(entry["destination"]))
      destinations.push(entry["destination"])
      source = entry["source"]
      if File.symlink?(source)
        target = Util.absolute(File.readlink(source), File.dirname(source))
        pointer = File.dirname(target)
        if File.basename(pointer) == "current" && File.symlink?(pointer) && File.file?(pointer + "/manifest.json")
          pins[pointer] = File.realpath(pointer) if !pins.has_key?(pointer)
          release = pins[pointer]
          manifest = JSON.parse(File.read(release + "/manifest.json"))
          items = manifest["files"].select ->(f) f["name"] == File.basename(target)
          raise "source absent from release manifest" if items.size != 1
          entry["source"] = release + "/" + items[0]["name"]
          entry["expected_sha256"] = items[0]["sha256"]
          entry["source_release"] = release
    raise "duplicate release destinations" if Util.unique(destinations).size != destinations.size
    File.mkdir_p(@directory)
    lock = Util.lock(@directory + "/.publish.lock")
    begin
      publish_locked(entries, provenance)
    ensure
      Util.unlock(lock)

  -> publish_locked(entries, provenance)
    current = @directory + "/current"
    mapping = Crypto.sha256(JSON.encode((entries.map ->(e) e["destination"]).sort))
    if File.symlink?(current)
      previous = JSON.parse(File.read(current + "/manifest.json"))
      raise "release destination set changed; use a new release directory" if previous["mapping"] != mapping
    elsif File.exist?(current)
      raise "current must be a symlink"
    id = Util.id()
    candidate = @directory + "/.candidate-" + id
    final = @directory + "/" + id
    File.mkdir_p(candidate)
    changed = []
    activated = false
    begin
      files = []
      i = 0
      entries.each ->(entry)
        src = entry["source"]
        raise "missing release source [src]" if !File.file?(src) || File.stat(src).size == 0
        name = "%02d" % i + "-" + File.basename(entry["destination"])
        path = candidate + "/" + name
        before = Util.sha(src)
        raise "source differs from its release manifest" if entry.has_key?("expected_sha256") && entry["expected_sha256"] != before
        Util.copy_file(src, path)
        raise "source changed during release copy" if Util.sha(src) != before || Util.sha(path) != before
        files.push({"name": name, "source": src, "destination": entry["destination"], "role": entry["role"], "sha256": before, "bytes": File.stat(path).size, "source_release": entry["source_release"]})
        i += 1
      i = 0
      entries.each ->(entry)
        item = files[i]
        reports = candidate + "/" + item["name"] + ".checks"
        File.mkdir_p(reports)
        result = @verify.call(candidate + "/" + item["name"], entry, reports)
        raise "candidate verification failed: [entry["source"]]" if result == nil || !result["ok"]
        item["verification"] = result
        i += 1
      report_hashes = {}
      files.each ->(item)
        raise "candidate changed during verification" if Util.sha(candidate + "/" + item["name"]) != item["sha256"]
      visitor = ->(path)
        if File.file?(path)
          Util.sync(path)
          report_hashes[path.slice(candidate.size + 1, path.size)] = Util.sha(path) if File.dirname(path) != candidate
      File.walk(candidate, visitor)
      Util.json(candidate + "/manifest.json", {"schema": 1, "release": id, "mapping": mapping, "provenance": provenance, "files": files, "reports": report_hashes})
      directories = []
      visitor = ->(path)
        directories.push(path) if File.directory?(path)
      File.walk(candidate, visitor)
      directories.sort.reverse.each ->(path)
        Util.sync(path)
      File.atomic_replace(candidate, final)
      if !File.symlink?(current)
        legacy = @directory + "/legacy-" + id
        File.mkdir_p(legacy)
        old_files = []
        i = 0
        entries.each ->(entry)
          dest = entry["destination"]
          if File.exist?(dest)
            name = files[i]["name"]
            Util.copy_file(dest, legacy + "/" + name)
            old_files.push({"name": name, "sha256": Util.sha(legacy + "/" + name)})
          i += 1
        Util.json(legacy + "/manifest.json", {"schema": 1, "legacy": true, "mapping": mapping, "files": old_files})
        Util.sync(legacy)
        Util.link_atomic(legacy, current)
      i = 0
      entries.each ->(entry)
        dest = entry["destination"]
        target = current + "/" + files[i]["name"]
        if !File.symlink?(dest) || File.readlink(dest) != target
          File.mkdir_p(File.dirname(dest))
          backup = dest + ".before-" + id
          existed = File.exist?(dest) || File.symlink?(dest)
          if File.symlink?(dest)
            File.symlink(File.readlink(dest), backup)
          elsif existed
            Util.copy_file(dest, backup)
          changed.push([dest, backup, existed])
          Util.link_atomic(target, dest)
        i += 1
      Util.barrier("before-activation")
      Util.link_atomic(final, current)
      activated = true
      Util.barrier("after-activation")
      final
    ensure
      changed.reverse.each ->(item)
        if !activated
          if item[2]
            File.atomic_replace(item[1], item[0])
          else
            Util.unlink(item[0])
        else
          Util.unlink(item[1]) if item[2]
      Util.remove_tree(candidate) if File.exist?(candidate)
