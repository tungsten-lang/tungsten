+ Directory
  -> .pwd
    file_pwd()

  -> .current
    file_pwd()

  -> .chdir(path)
    if block?
      previous = file_pwd()
      file_chdir(path)
      result = yield
      file_chdir(previous)
      return result
    file_chdir(path)

  -> .cd(path)
    if block?
      previous = file_pwd()
      file_chdir(path)
      result = yield
      file_chdir(previous)
      return result
    file_chdir(path)

  -> .entries(path = ".")
    read_dir(path)

  -> .children(path = ".")
    read_dir(path)

  -> .read(path = ".")
    read_dir(path)

  -> .ls(path = ".")
    read_dir(path)

  -> .each(path = ".", &)
    read_dir(path).each -> (entry)
      yield entry

  -> .foreach(path = ".", &)
    read_dir(path).each -> (entry)
      yield entry

  -> .each_child(path = ".", &)
    read_dir(path).each -> (entry)
      yield entry

  -> .walk(path = ".", block = nil)
    File.walk(path, block)

  -> .exist?(path)
    file_directory?(path)

  -> .exists?(path)
    file_directory?(path)

  -> .directory?(path)
    file_directory?(path)

  -> .empty?(path = ".")
    read_dir(path).size == 0

  -> .mkdir(path, *opts)
    opt = opts.size > 0 ? opts[0] : nil
    file_mkdir(path, opt)

  -> .mkdir_p(path)
    file_mkdir(path, recursive: true)

  -> .rmdir(path)
    file_rmdir(path)
