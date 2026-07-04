# IO — input/output primitives
#
# Standard I/O:
#   << "hello"          Print with newline (puts)
#   <- "hello"          Print without newline (print)
#   gets                Read a line from stdin
#   read_bytes(n)       Read exactly n bytes from stdin
#   flush               Flush stdout
#   log "msg"           Write to stderr
#
# Files:
#   read_file(path)     Read entire file as string
#   write_file(path, s) Write string to file
#   file?(path)         True if file exists
#
# Processes:
#   system(cmd)         Run a shell command, return success boolean
#   capture(cmd)        Run a shell command, return stdout as string
#
# Pipes:
#   IO.popen(cmd, input)    Run a command, pipe input to stdin, return stdout
#   IO.popen_ok?(cmd, input) Same but return success boolean

+ IO
  -> .popen(cmd, input)
    result = popen(cmd, input)
    result[0]

  -> .popen_ok?(cmd, input)
    result = popen(cmd, input)
    result[1]
