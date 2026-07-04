# OS — operating system interface
#
# Everything here is about the world outside this process.
# For process-level operations, see W.

+ OS
  # Commands
  -> .capture(cmd)       # run command, return stdout as string
  -> .system(cmd)        # run command, return exit status

  # Filesystem
  -> .directory?(path)
  -> .exists?(path)
  -> .file_mtime_ns(path)
  -> .file_size(path)
  -> .read_file(path)    # read file contents as string
  -> .read_file_bytes(path)
  -> .read_dir(path)
  -> .write_file(path, data)
  -> .file?(path)        # does the path exist?

  # Platform
  -> .platform           # "macos", "linux", etc.
  -> .arch               # "x86_64", "arm64", etc.
