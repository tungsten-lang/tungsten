+ Directory
  -> .pwd
    file_pwd()

  -> .current
    file_pwd()

  -> .chdir(path)
    if block_given?
      file_chdir(path) ->
        yield
    else
      file_chdir(path)

  -> .cd(path)
    if block_given?
      file_chdir(path) ->
        yield
    else
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

  -> .exist?(path)
    file_directory?(path)

  -> .exists?(path)
    file_directory?(path)

  -> .directory?(path)
    file_directory?(path)

  -> .empty?(path = ".")
    read_dir(path).size == 0

  -> .mkdir(path, *opts)
    file_mkdir(path, *opts)

  -> .mkdir_p(path)
    file_mkdir(path, recursive: true)

  -> .rmdir(path)
    file_rmdir(path)
