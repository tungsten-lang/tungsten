use flipfleet_live_store

-> fflst_expect(label, condition) i64
  if condition == 0
    << "FAIL " + label
    return 1
  0

failures = 0 ## i64
root = "/tmp/metaflip live store"

failures += fflst_expect("configured root wins", ffls_root(root) == root)
expected_default = env("METAFLIP_HOME")
if expected_default == nil || expected_default == ""
  expected_home = env("HOME")
  if expected_home != nil && expected_home != ""
    expected_default = expected_home + "/.tungsten/metaflip"
  if expected_home == nil || expected_home == ""
    expected_default = ""
failures += fflst_expect("environment root precedence", ffls_root("") == expected_default)
failures += fflst_expect("square label is full tensor", ffls_shape_label("5x5", 5) == "5x5x5")
failures += fflst_expect("rectangular label is preserved", ffls_shape_label("3x4x6", 0) == "3x4x6")
failures += fflst_expect("checkpoint path", ffls_best_path(root, "gf2", "5x5x5") == root + "/checkpoints/gf2/5x5x5/best.txt")
failures += fflst_expect("status path", ffls_status_path(root, "gf2", "5x5x5", "run-17") == root + "/runs/gf2/5x5x5/run-17/status.txt")
failures += fflst_expect("bank path", ffls_bank_dir(root, "gf2", "5x5x5") == root + "/banks/gf2/5x5x5")

nonce = ccall("__w_clock_ms").to_s()
directory = "/tmp/flipfleet_live_store_test_" + nonce + "/nested dir's"
failures += fflst_expect("directory creation", ffls_ensure_dir(directory) == 1 && system("test -d " + ffls_shell_quote(directory)))
failures += fflst_expect("newline rejected", ffls_ensure_dir("/tmp/bad\npath") == 0)
z = system("rm -rf " + ffls_shell_quote("/tmp/flipfleet_live_store_test_" + nonce))

if failures == 0
  << "PASS flipfleet live-store paths"
  exit(0)
<< "FAIL flipfleet live-store paths failures=" + failures.to_s()
exit(1)
