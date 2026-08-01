# Sandbox mode: the runtime gate over everything outside the process.
#
# Dual-mode by design, so one file covers both halves of the contract:
#   bin/tungsten -o /tmp/sbx spec/core/sandbox_spec.w && /tmp/sbx
#       -> gate OFF: real IO still works, nothing is logged (zero impact)
#   bin/tungsten sandbox spec/core/sandbox_spec.w
#       -> gate ON: actions raise, observations stub, attempts are counted
#
# Self-contained on purpose: it writes its own probe file rather than reading a
# path in the repo, so it does not depend on the working directory or on this
# file's own name. See core/sandbox.w for the op list.

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

probe = "/tmp/tungsten_sandbox_spec_probe.txt"
payload = "sandbox probe payload"

active = Sandbox.active?
check("sandbox.class_resolves", active == true || active == false)

# Blocked ACTION: writing a file.
write_raised = false
begin
  File.write(probe, payload)
rescue e
  write_raised = true
  check("sandbox.write.error_names_op", "[e]".include?("write_file") == true)

# Blocked ACTION: reading a file. The gate fires before the path is touched, so
# this raises under the sandbox whether or not the write above landed.
read_raised = false
read_back = nil
begin
  read_back = File.read(probe)
rescue e2
  read_raised = true
  check("sandbox.read.error_names_op", "[e2]".include?("read_file") == true)

# Blocked ACTION: shelling out.
system_raised = false
begin
  OS.system("true")
rescue e3
  system_raised = true
  check("sandbox.system.error_names_op", "[e3]".include?("system") == true)

# Blocked ACTION: deleting a file. The atomic-publish family (unlink, mkdir_p,
# temp_file_for, fsync_*, append_file_to) reaches the filesystem without going
# through File.read/File.write, and was ungated until an extern-level audit
# caught it — unlink DELETES, so this one is load-bearing.
# Targets a throwaway path, not `probe`: unsandboxed this really deletes, and
# deleting the probe would break the File.exist? observation below.
unlink_raised = false
begin
  ccall("__w_unlink", probe + ".delete_me")
rescue e4
  unlink_raised = true
  check("sandbox.unlink.error_names_op", "[e4]".include?("unlink") == true)

# Stubbed OBSERVATIONS: benign values, never a raise.
home = env("HOME")
exists = File.exist?(probe)

attempts = Sandbox.attempts

if active
  check("sandbox.on.write_blocked", write_raised == true)
  check("sandbox.on.read_blocked", read_raised == true)
  check("sandbox.on.system_blocked", system_raised == true)
  check("sandbox.on.env_stubbed_nil", home == nil)
  check("sandbox.on.exist_stubbed_false", exists == false)
  check("sandbox.on.unlink_blocked", unlink_raised == true)
  # write + read + system + unlink + env + exist? — every gated op is counted.
  check("sandbox.on.attempts_counted", attempts >= 6)
else
  check("sandbox.off.write_works", write_raised == false)
  check("sandbox.off.read_works", read_raised == false && read_back == payload)
  check("sandbox.off.system_works", system_raised == false)
  check("sandbox.off.env_real", home != nil)
  check("sandbox.off.exist_real", exists == true)
  check("sandbox.off.unlink_works", unlink_raised == false)
  check("sandbox.off.no_attempts", attempts == 0)

# Pure computation is never gated, in either mode.
total = 0 ## i64
i = 0 ## i64
while i < 100
  total += i * i
  i += 1
check("sandbox.compute_unaffected", total == 328350)
