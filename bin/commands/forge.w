# tungsten forge — compile and run a Forge HTTP app
#
# Usage:
#   tungsten forge [FILE.w] [--port PORT] [--workers N]
#   tungsten forge start [FILE.w] [--port PORT]
#   tungsten forge stop

args = argv()
port = 7474
workers = 4
subcommand = nil
source_file = nil
max_mode = false
capacity_headers = false

i = 0
while i < args.size
  a = args[i]
  if a == "start" || a == "stop"
    if subcommand == nil
      subcommand = a
    else
      source_file = a
  elsif a == "-p" || a == "--port"
    i = i + 1
    if i < args.size
      port = args[i].to_i
  elsif a == "-w" || a == "--workers"
    i = i + 1
    if i < args.size
      workers = args[i].to_i
  elsif a == "--max"
    max_mode = true
  elsif a == "--capacity"
    capacity_headers = true
  elsif a == "-h" || a == "--help"
    << "Usage: tungsten forge start|stop FILE --port PORT --workers N"
    << ""
    << "  start   compile, daemonize, write ~/.tungsten/forge.pid"
    << "  stop    kill the daemon"
    << "  (none)  compile and run in the foreground"
    exit(0)
  elsif a.starts_with?("-")
    << "tungsten forge: unknown option " + a
    exit(1)
  else
    source_file = a
  i = i + 1

home = env("HOME")
if home == nil
  home = "/tmp"
pid_dir = home + "/.tungsten"
pid_file = pid_dir + "/forge.pid"
forge_dir = pid_dir + "/forge"
root = env("TUNGSTEN_ROOT")
if root == nil
  root = "."
compiler = root + "/bin/tungsten-compiler"

-> default_source(port, workers)
  "use Forge\n\nForge.configure ->\n  host \"127.0.0.1\"\n  port " + port.to_s + "\n  workers " + workers.to_s + "\n\nForge.routes ->\n  get \"/\" -> (request)\n    Response.ok(\"Welcome to Forge\")\n\n  get \"/health\" -> (request)\n    Response.json({status: \"ok\"})\n\nForge.start\n"

-> read_pid(pid_file)
  if !system("test -f '" + pid_file + "'")
    return nil
  text = read_file(pid_file).strip
  if text == ""
    return nil
  pid = text.to_i
  if pid <= 0
    return nil
  # alive?
  if system("kill -0 " + pid.to_s + " 2>/dev/null")
    return pid
  system("rm -f '" + pid_file + "'")
  nil

-> compile_app(source_file, bin_path, port, workers)
  src = source_file
  tmp_src = nil
  if src == nil
    system("mkdir -p /tmp")
    tmp_src = "/tmp/tungsten-forge-app.w"
    write_file(tmp_src, default_source(port, workers))
    src = tmp_src
  if !system("test -f '" + src.gsub("'", "'\\''") + "'")
    << "tungsten forge: file not found: " + src
    exit(1)
  # BIT_HOME so `use Forge` resolves
  root = env("TUNGSTEN_ROOT")
  if root == nil
    root = "."
  compiler = root + "/bin/tungsten-compiler"
  cmd = "BIT_HOME='" + root + "/bits' '" + compiler + "' compile '" + src + "' --out '" + bin_path + "' --no-lto"
  ok = system(cmd + " >/dev/null 2>&1")
  if tmp_src != nil
    system("rm -f '" + tmp_src + "'")
  ok

if subcommand == "stop"
  pid = read_pid(pid_file)
  if pid == nil
    << "No forge server running"
    exit(0)
  system("kill " + pid.to_s + " 2>/dev/null")
  system("rm -f '" + pid_file + "'")
  << "Stopped forge server (pid " + pid.to_s + ")"
  exit(0)

system("mkdir -p '" + forge_dir + "'")
bin_path = forge_dir + "/server"

print "Compiling..."
if !compile_app(source_file, bin_path, port, workers)
  << ""
  << "Compile failed"
  exit(1)
<< "\rCompiled           "

env_prefix = ""
if max_mode
  env_prefix = env_prefix + "TUNGSTEN_FORGE_MAX=1 "
if capacity_headers && !max_mode
  env_prefix = env_prefix + "TUNGSTEN_FORGE_CAPACITY=1 "

if subcommand == "start"
  existing = read_pid(pid_file)
  if existing != nil
    << "Forge already running (pid " + existing.to_s + ")"
    exit(1)
  # daemonize
  cmd = env_prefix + "'" + bin_path + "' >/dev/null 2>&1 & echo $!"
  pid_s = capture(cmd).strip
  write_file(pid_file, pid_s + "\n")
  # wait briefly for listen
  system("sleep 0.5")
  << "forge started on http://127.0.0.1:" + port.to_s + "/ (pid " + pid_s + ")"
  exit(0)

# Foreground
<< "forge listening on http://127.0.0.1:" + port.to_s + "/"
<< "Ctrl+C to stop"
<< ""
if env_prefix != ""
  system(env_prefix + "exec '" + bin_path + "'")
else
  system("exec '" + bin_path + "'")
