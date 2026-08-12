use core/mmap

# FileStat — portable POSIX file metadata with nanosecond timestamps.
+ FileStat
  -> new(@path, @data)

  -> path
    @path

  -> dev
    @data[0]

  -> ino
    @data[1]

  -> mode
    @data[2]

  -> permissions
    mode() & 0o7777

  -> nlink
    @data[3]

  -> uid
    @data[4]

  -> gid
    @data[5]

  -> rdev
    @data[6]

  -> size
    @data[7]

  -> blksize
    @data[8]

  -> blocks
    @data[9]

  -> atime_ns
    @data[10]

  -> mtime_ns
    @data[11]

  -> ctime_ns
    @data[12]

  # nil on hosts whose stat structure has no creation/birth timestamp.
  -> birthtime_ns
    @data[13]

  -> type
    @data[14]

  -> file?
    @data[14] == "file"

  -> directory?
    @data[14] == "directory"

  -> symlink?
    @data[14] == "symlink"

# File — whole-file I/O, metadata, paths, and filesystem operations.
+ File
  # Managed handles
  -> .open(path, *args)
    mode = args.size > 0 ? args[0] : "r"
    if block?
      file_open(path, mode) -> (file)
        yield file
    else
      file_open(path, mode)

  # Whole-file reads/writes
  -> .read(path)
    read_file(path)

  -> .read_bytes(path)
    read_file_bytes(path)

  -> .binread(path)
    read_file_bytes(path)

  -> .write(path, *args)
    if block?
      mode = args.size > 0 ? args[0] : "w"
      file_open(path, mode) -> (file)
        yield file
    else
      write_file(path, args[0])

  -> .write_bytes(path, data)
    write_file_bytes(path, data)

  -> .binwrite(path, data)
    write_file_bytes(path, data)

  # Metadata and predicates
  -> .exist?(path)
    file_exists?(path)

  -> .exists?(path)
    file_exists?(path)

  -> .file?(path)
    file_file?(path)

  -> .directory?(path)
    file_directory?(path)

  -> .dir?(path)
    file_directory?(path)

  -> .symlink?(path)
    file_symlink?(path)

  -> .type(path)
    file_type(path)

  -> .file_type(path)
    file_type(path)

  -> .size(path)
    file_size(path)

  -> .stat(path)
    data = file_stat_data(path, true)
    return nil if data == nil
    FileStat.new(path, data)

  # Like stat, but preserves a symbolic link as the result instead of
  # following it to its target.
  -> .lstat(path)
    data = file_stat_data(path, false)
    return nil if data == nil
    FileStat.new(path, data)

  -> .mtime(path)
    file_mtime(path)

  -> .mtime_ns(path)
    file_mtime_ns(path)

  -> .atime(path)
    file_atime(path)

  -> .ctime(path)
    file_ctime(path)

  # Directory listing
  -> .entries(path = ".")
    read_dir(path)

  -> .children(path = ".")
    read_dir(path)

  -> .read_dir(path = ".")
    ccall("__w_file_read_dir", path)

  -> .ls(path = ".")
    read_dir(path)

  -> .each_entry(path = ".", &)
    read_dir(path).each -> (entry)
      yield entry

  -> .each_child(path = ".", &)
    read_dir(path).each -> (entry)
      yield entry

  # Depth-first traversal. lstat deliberately prevents a symbolic link to a
  # directory from becoming a recursive edge (and therefore prevents cycles).
  -> .walk(path = ".", block = nil)
    raise "File.walk requires a visitor" if block == nil
    pending = [path]
    while pending.size > 0
      current = pending.pop()
      block(current)
      metadata = File.lstat(current)
      if metadata != nil && metadata.directory?()
        read_dir(current).each -> (entry)
          pending.push(File.join(current, entry))
    path

  # Filesystem mutation
  -> .chdir(dir)
    if block?
      file_chdir(dir) ->
        yield
    else
      file_chdir(dir)

  -> .cd(dir)
    if block?
      file_chdir(dir) ->
        yield
    else
      file_chdir(dir)

  -> .pwd
    file_pwd()

  -> .mkdir(path, *opts)
    file_mkdir(path, *opts)

  -> .mkdir_p(path)
    file_mkdir(path, recursive: true)

  -> .rmdir(path)
    file_rmdir(path)

  -> .rm(path, *opts)
    file_rm(path, *opts)

  -> .delete(path)
    ok = file_unlink_strict(path)
    raise "File.delete failed: " + path unless ok
    true

  -> .unlink(path)
    ok = file_unlink_strict(path)
    raise "File.unlink failed: " + path unless ok
    true

  -> .mv(source, dest, *opts)
    file_mv(source, dest, *opts)

  -> .rename(source, dest)
    ok = file_rename(source, dest)
    raise "File.rename failed: " + source + " -> " + dest unless ok
    true

  -> .cp(source, dest, *opts)
    file_cp(source, dest, *opts)

  -> .touch(path)
    file_touch(path)

  -> .symlink(target, link_name)
    file_symlink(target, link_name)

  -> .ln_s(target, link_name)
    file_symlink(target, link_name)

  -> .link(target, link_name)
    ok = file_link(target, link_name)
    raise "File.link failed: " + target + " -> " + link_name unless ok
    true

  -> .chmod(path, mode)
    if mode < 0 || mode > 0o7777
      raise "File.chmod mode must be between 0o0000 and 0o7777"
    ok = file_chmod(path, mode)
    raise "File.chmod failed: " + path unless ok
    true

  # Atomically replace destination with an already-written source on the same
  # filesystem, then make the directory entry durable. A failure after rename
  # means the replacement is visible but its crash durability is uncertain.
  -> .atomic_replace(source, destination)
    ok = file_rename(source, destination)
    raise "File.atomic_replace failed: " + source + " -> " + destination unless ok
    durable = file_fsync_parent(destination)
    raise "File.atomic_replace directory sync failed: " + destination unless durable
    true

  # Write beside the destination, flush the file, atomically rename it over the
  # destination, then flush the parent directory. Existing permissions are
  # preserved; a new file starts mode 0600. The temp path is always cleaned up
  # if publication does not consume it.
  -> .atomic_write(path, data)
    temporary = file_temp_for(path)
    raise "File.atomic_write could not create a sibling temporary file: " + path if temporary == nil
    published = false
    begin
      existing = File.stat(path)
      if existing != nil
        ok = file_chmod(temporary, existing.permissions)
        raise "File.atomic_write could not preserve permissions: " + path unless ok
      ok = write_file(temporary, data)
      raise "File.atomic_write failed while writing: " + path unless ok
      ok = file_fsync(temporary)
      raise "File.atomic_write failed while syncing: " + path unless ok
      ok = file_rename(temporary, path)
      raise "File.atomic_write failed while publishing: " + path unless ok
      published = true
      ok = file_fsync_parent(path)
      raise "File.atomic_write failed while syncing the parent: " + path unless ok
    ensure
      file_unlink(temporary) unless published
    data.size

  -> .readlink(path)
    file_readlink(path)

  -> .realpath(path)
    file_realpath(path)

  -> .expand_path(path, *args)
    if args.size > 0
      file_expand_path_base(path, args[0])
    else
      file_expand_path(path)

  -> .join(*parts)
    return "" if parts.size == 0
    joined = parts[0]
    i = 1
    while i < parts.size
      joined = file_join(joined, parts[i])
      i += 1
    joined

  -> .basename(path)
    file_basename(path)

  -> .dirname(path)
    file_dirname(path)

  -> .extname(path)
    file_extname(path)

# Tempfile — a securely-created, path-owning temporary file.
# `create` with a block is the preferred
# form: cleanup runs through ensure even when the block raises. The non-block
# form transfers unlink ownership to the caller, which should use close!.
+ Tempfile
  -> new(prefix = "tungsten", directory = nil)
    @path = tempfile_create(prefix, directory)
    if @path == nil
      raise "could not create temporary file"
    @closed = false
    @unlinked = false

  -> .create(prefix = "tungsten", directory = nil, &)
    tempfile = Tempfile.new(prefix, directory)
    if block?
      begin
        yield tempfile
      ensure
        tempfile.close!()
    else
      tempfile

  -> path
    @path

  -> write(data)
    raise "closed tempfile" if @closed
    written = write_file(@path, data)
    return false if written == false
    data.size

  -> write_bytes(data)
    raise "closed tempfile" if @closed
    written = write_file_bytes(@path, data)
    return false if written == false
    data.size

  -> read
    raise "closed tempfile" if @closed
    read_file(@path)

  -> read_bytes
    raise "closed tempfile" if @closed
    read_file_bytes(@path)

  -> size
    file_size(@path)

  -> stat
    File.stat(@path)

  -> exist?
    file_exists?(@path)

  -> closed?
    @closed

  -> close
    @closed = true
    nil

  -> unlink
    if !@unlinked
      removed = file_unlink(@path)
      @unlinked = true if removed
    nil

  -> delete
    unlink()

  -> close!
    close()
    unlink()

  -> to_s
    @path
