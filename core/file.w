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
    read_dir(path)

  -> .ls(path = ".")
    read_dir(path)

  -> .each_entry(path = ".", &)
    read_dir(path).each -> (entry)
      yield entry

  -> .each_child(path = ".", &)
    read_dir(path).each -> (entry)
      yield entry

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
    file_rm(path)

  -> .unlink(path)
    file_rm(path)

  -> .mv(source, dest, *opts)
    file_mv(source, dest, *opts)

  -> .rename(source, dest)
    file_mv(source, dest)

  -> .cp(source, dest, *opts)
    file_cp(source, dest, *opts)

  -> .touch(path)
    file_touch(path)

  -> .symlink(target, link_name)
    file_symlink(target, link_name)

  -> .ln_s(target, link_name)
    file_symlink(target, link_name)

  -> .link(target, link_name)
    file_link(target, link_name)

  -> .readlink(path)
    file_readlink(path)

  -> .realpath(path)
    file_realpath(path)

  -> .expand_path(path, *args)
    if args.size > 0
      file_expand_path(path, args[0])
    else
      file_expand_path(path)

  -> .join(*parts)
    file_join(*parts)

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
