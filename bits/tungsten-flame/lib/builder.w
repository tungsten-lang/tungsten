# builder.w — Compile .w files for profiling.
#
# Shells out to the standard `tungsten-compiler compile --frame-pointers`
# invocation. `--frame-pointers` keeps frame pointers in the emitted
# binary so the sampler can walk stacks accurately.
#
# Stage C (sampler.w) will gain a looping-main wrapper for short-lived
# binaries — that LLVM-IR mutation is sampling-domain concern, kept out
# of Builder so this module stays small and reusable.

in Tungsten:Flame

+ Builder

  # Compile `source_path` to a native binary at `out_path`. Returns true
  # on success, false on failure. Caller is responsible for checking.
  -> .compile(source_path, out_path)
    compiler = self.compiler_bin()
    src_q = self.shell_quote(source_path)
    out_q = self.shell_quote(out_path)
    cmd = compiler + " compile --frame-pointers " + src_q + " --out " + out_q
    system(cmd)

  # Locate the compiler binary. Prefers $TUNGSTEN_ROOT/bin/tungsten-compiler;
  # falls back to bare `tungsten-compiler` on $PATH so a deployment that
  # installs the binary elsewhere still works.
  -> .compiler_bin()
    root = self.project_root()
    candidate = root + "/bin/tungsten-compiler"
    if file?(candidate)
      candidate
    else
      "tungsten-compiler"

  # Project root, computed relative to this file's location
  # (`bits/tungsten-flame/lib/builder.w` → three levels up).
  -> .project_root()
    __DIR__ + "/../../.."

  # POSIX-safe single-quote escaping.
  -> .shell_quote(s)
    "'" + s.replace("'", "'\\''") + "'"
