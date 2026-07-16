use core/system

path = System.executable_path
dir = System.executable_dir

if path == nil || path == "" || !path.starts_with?("/") || !file?(path)
  << "system executable_path FAILED: " + path.to_s
  exit(1)

if dir == nil || dir == "" || !dir.starts_with?("/")
  << "system executable_dir FAILED: " + dir.to_s
  exit(1)

dir_probe = capture("test -d '" + dir.replace("'", "'\\''") + "' && echo yes")
if dir_probe == nil || dir_probe.strip() != "yes"
  << "system executable_dir missing FAILED: " + dir
  exit(1)

path_prefix = dir
path_prefix = path_prefix + "/" if dir != "/"
if !path.starts_with?(path_prefix)
  << "system executable path/dir mismatch FAILED: " + path + " / " + dir
  exit(1)

count = System.cpu_count ## i64
if count < 1
  << "system cpu_count FAILED"
  exit(1)

<< "system executable_path ok: " + path
<< "system executable_dir ok: " + dir
<< "system cpu_count ok: " + count.to_s()
