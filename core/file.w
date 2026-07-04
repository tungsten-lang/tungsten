+ File
  # Managed handles
  -> .open(path, *args)
    mode = args.size > 0 ? args[0] : "r"
    if block_given?
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
    if block_given?
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
    if block_given?
      file_chdir(dir) ->
        yield
    else
      file_chdir(dir)

  -> .cd(dir)
    if block_given?
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

# Mmap — return type of File.mmap. Borrowed view of file bytes.
+ Mmap
  -> length
  -> size
  -> byte_at(i)
  -> [](i)
  -> as_u8
  -> as_u16
  -> as_u32
  -> as_u64
  -> as_i8
  -> as_i16
  -> as_i32
  -> as_i64
  -> as_f32
  -> as_f64
  -> view_at(byte_offset, ebits, n_elements)
  -> close
