# Process.spawn must give posix_spawnp stable ownership of every argument.
#
# Inline strings are converted through a small runtime ring.  Retaining the
# returned pointers while converting more arguments used to let the ring wrap
# and silently replace an earlier argument.  Keep enough short strings here to
# exercise multiple wraps, with a long shell predicate checking every slot.

command = "test \"$0\" = marker && test \"$1\" = a && test \"$2\" = b && test \"$3\" = c && test \"$4\" = d && test \"$5\" = e"
process = Process.spawn([
  "/bin/sh",
  "-c",
  command,
  "marker",
  "a",
  "b",
  "c",
  "d",
  "e"
])

status = process.wait
if status != 0
  << "FAIL Process.spawn argv ownership status=" + status.to_s()
  exit(1)

<< "PASS Process.spawn argv ownership"
