module Tungsten
  # Single source of truth: the repo-root VERSION file, read at runtime (no
  # codegen). bin/tungsten.w and the bash wrapper read the same file, so the
  # version can't drift across the Ruby CLI, the compiled CLI, and the REPL.
  VERSION = begin
    File.read(File.expand_path("../../../../../VERSION", __FILE__)).strip
  rescue StandardError
    "0.0.0-unknown"
  end
end
