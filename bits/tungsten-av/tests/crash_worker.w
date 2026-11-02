use ../lib/av
args = argv()
root = args[1]
if args[0] == "publish"
  entries = []
  ["master.mov", "share.mp4"].each ->(name)
    entries.push({"source": root + "/" + name, "destination": root + "/published/" + name, "role": name})
  check = ->(path, entry, reports)
    {"ok": true}
  << Av:Publisher.new(root + "/releases", check).publish(entries, {})
elsif args[0] == "supervise"
  File.atomic_write(root + "/parent.pid", ccall("w_av_pid").to_s)
  Av:Runner.new(30).run(["/bin/sh", "-c", "sleep 30 & echo $! > \"$1\"; wait", "sh", root + "/child.pid"])
