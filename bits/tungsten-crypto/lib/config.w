# User configuration, read from ~/.tungsten/crypto.config.
#
# Format is `key = value`, one per line. `#` starts a comment, blank lines are
# ignored, and whitespace around the key and value is stripped. Unknown keys
# are kept rather than rejected, so a newer config does not break an older
# binary.
#
# Precedence everywhere is: command line > config file > built-in default.
# The command line always wins, so a config can never silently override
# something typed explicitly — which for the payout address is the difference
# between mining to yourself and mining to someone else.

CRYPTO_CONFIG_PATH = "/.tungsten/crypto.config"

# Absolute path of the config file, or nil if HOME is unset.
-> crypto_config_path
  h = env("HOME")
  if h == nil || h == ""
    return nil
  h + CRYPTO_CONFIG_PATH

# Parse the config into a hash. Returns an empty hash when the file is
# absent — a missing config is the normal case, not an error.
-> crypto_config_load
  p = crypto_config_path()
  if p == nil
    return {}
  # read_file returns nil for a missing file, so no existence check is
  # needed (and none is reachable from the interpreter anyway).
  text = read_file(p)
  if text == nil
    return {}
  crypto_config_parse(text)

-> crypto_config_parse(text)
  out = {}
  lines = text.split("\n")
  i = 0
  while i < lines.size
    line = lines[i]
    # Strip comments first, so `key = value  # note` works.
    hash_at = line.index("#")
    if hash_at != nil
      line = line.slice(0, hash_at)
    eq = line.index("=")
    if eq != nil
      key = line.slice(0, eq).strip()
      val = line.slice(eq + 1, line.size - eq - 1).strip()
      if key != "" && val != ""
        out[key] = val
    i += 1
  out

# A single value, or `fallback` when the key is absent or empty.
-> crypto_config_get(cfg, key, fallback)
  if cfg == nil
    return fallback
  v = cfg[key]
  if v == nil || v == ""
    return fallback
  v
