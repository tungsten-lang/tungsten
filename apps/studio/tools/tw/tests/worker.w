# Fixture for the outer AV stage supervisor: worker groups and OS.system.
a = argv()
if a[0] == "system"
  exit(OS.system(a[1]) ? 0 : 1)
p = Process.spawn(a[1...a.size])
exit(p.wait)
