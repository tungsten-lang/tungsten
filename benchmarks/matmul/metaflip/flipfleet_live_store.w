# Live-state path policy shared by the native GF(2) coordinators.
#
# Published schemes remain repository/results assets.  Mutable checkpoints,
# restart banks, and run heartbeats live under one user-owned root instead of
# depending on the launch directory.  Explicit CLI paths are resolved by the
# coordinator and deliberately bypass these helpers.

-> ffls_root(configured) (String)
  if configured != ""
    return configured
  override = env("METAFLIP_HOME")
  if override != nil && override != ""
    return override
  home = env("HOME")
  if home != nil && home != ""
    return home + "/.tungsten/metaflip"
  ""

-> ffls_shape_label(tensor, square_n) (String i64)
  if square_n > 0
    return square_n.to_s() + "x" + square_n.to_s() + "x" + square_n.to_s()
  tensor

-> ffls_checkpoint_dir(root, domain, shape) (String String String)
  root + "/checkpoints/" + domain + "/" + shape

-> ffls_best_path(root, domain, shape) (String String String)
  ffls_checkpoint_dir(root, domain, shape) + "/best.txt"

-> ffls_run_dir(root, domain, shape, run_tag) (String String String String)
  root + "/runs/" + domain + "/" + shape + "/" + run_tag

-> ffls_status_path(root, domain, shape, run_tag) (String String String String)
  ffls_run_dir(root, domain, shape, run_tag) + "/status.txt"

-> ffls_bank_dir(root, domain, shape) (String String String)
  root + "/banks/" + domain + "/" + shape

-> ffls_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffls_ensure_dir(path) (String) i64
  if path == "" || path.include?("\n")
    return 0
  made = system("mkdir -p " + ffls_shell_quote(path))
  if made
    return 1
  0
