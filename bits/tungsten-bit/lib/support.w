# Support objects for the bit command implementations.

in Tungsten:Bit

DEFAULT_REGISTRY = "https://bits.tungsten-lang.org"

-> shell_quote(value)
  s = value.to_s
  "'" + s.replace("'", "'\\''") + "'"

+ File
  -> .join(left, right)
    base = left.to_s
    part = right.to_s
    if base.ends_with?("/")
      base + part
    else
      base + "/" + part

  -> .exists?(path)
    system("test -e " + shell_quote(path))

  -> .exist?(path)
    File.exists?(path)

  -> .read(path)
    read_file(path)

  -> .write(path, content)
    write_file(path, content)

+ Dir
  -> .pwd
    env("PWD") || "."

  -> .exists?(path)
    system("test -d " + shell_quote(path))

  -> .exist?(path)
    Dir.exists?(path)

  -> .chdir(path, &block)
    yield

  -> .glob(pattern)
    if pattern == "lib/**/*.w"
      out = capture("find lib -type f -name '*.w' 2>/dev/null | sort")
    else
      out = capture("find " + shell_quote(pattern) + " -type f 2>/dev/null | sort")
    if out == nil || out.strip() == ""
      return []
    out.strip().split("\n")

+ FileUtils
  -> .mkdir_p(path)
    system("mkdir -p " + shell_quote(path))

  -> .rm_rf(path)
    system("rm -rf " + shell_quote(path))

  -> .cp_r(src, dest)
    system("cp -R " + shell_quote(src) + " " + shell_quote(dest))

+ System
  -> .cpu_count
    n = capture("sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 1").strip().to_i
    if n <= 0
      1
    else
      n

  -> .target_triple
    triple = capture("clang -dumpmachine 2>/dev/null").strip()
    if triple == ""
      "native"
    else
      triple

  -> .exec(command)
    system(command)

-> project_class_name(name)
  out = ""
  name.to_s.replace("-", "_").split("_").each -> (part)
    if part != ""
      out = out + part.capitalize()
  out

-> bit_home
  env("BIT_HOME") || "bits"

-> default_bit_source
  if env("BIT_HOME") != nil
    bit_home()
  else
    DEFAULT_REGISTRY

-> executable_file?(path)
  system("test -x " + shell_quote(path))

# Resolve the Tungsten driver used by `bit build`. Application bits are often
# built outside the Tungsten source checkout, so a checkout-local compiler
# cannot be the only option. Explicit overrides win; source-checkout paths stay
# ahead of PATH to preserve the historical in-tree behavior.
-> tungsten_compiler_command
  override = env("TUNGSTEN_COMPILER")
  if override != nil && override.strip() != ""
    return override.strip()

  override = env("TUNGSTEN")
  if override != nil && override.strip() != ""
    return override.strip()

  root = env("TUNGSTEN_ROOT")
  if root != nil && root.strip() != ""
    driver = File.join(root.strip(), "bin/tungsten")
    return driver if executable_file?(driver)
    compiler = File.join(root.strip(), "bin/tungsten-compiler")
    return compiler if executable_file?(compiler)

  return "bin/tungsten" if executable_file?("bin/tungsten")
  return "bin/tungsten-compiler" if executable_file?("bin/tungsten-compiler")

  path = capture("command -v tungsten 2>/dev/null").strip()
  return path if path != ""

  path = capture("command -v tungsten-compiler 2>/dev/null").strip()
  return path if path != ""

  nil

-> safe_package_path?(path)
  value = path.to_s.strip()
  return false if value == ""
  return false if value.starts_with?("/")
  return false if value == ".." || value.starts_with?("../")
  return false if value.index("/../") != nil || value.ends_with?("/..")
  true

-> path_parent(path)
  parts = path.to_s.split("/")
  if parts.size() <= 1
    return "."
  parts.pop()
  parts.join("/")

-> append_unique(values, value)
  if value != nil && !values.include?(value)
    values.push(value)

-> package_path_within?(path, parent)
  path == parent || path.starts_with?(parent + "/")

-> append_uncovered_path(paths, path)
  covered = false
  paths.each -> (existing)
    if package_path_within?(path, existing)
      covered = true
  if covered
    return paths

  kept = []
  paths.each -> (existing)
    if !package_path_within?(existing, path)
      kept.push(existing)
  kept.push(path)
  kept

-> packaged_asset_paths(bitfile)
  paths = []
  paths = append_uncovered_path(paths, "assets") if File.exists?("assets")
  bitfile.assets.each -> (path)
    paths = append_uncovered_path(paths, path)
  paths

-> bit_config_home
  env("BIT_CONFIG_HOME") || File.join(env("HOME") || ".", ".bit")

-> bit_profile_path
  File.join(bit_config_home(), "profile")

-> bit_credentials_path
  File.join(bit_config_home(), "credentials")

-> ensure_bit_config_home
  FileUtils.mkdir_p(bit_config_home())

-> file_size_human(path)
  raw = capture("wc -c < " + shell_quote(path) + " 2>/dev/null").strip()
  bytes = raw.to_i
  if bytes < 1024
    return bytes.to_s + "B"
  kb = bytes / 1024
  if kb < 1024
    return kb.to_s + "KB"
  (kb / 1024).to_s + "MB"

-> remote_url?(value)
  s = value.to_s
  s.starts_with?("https://") || s.starts_with?("http://")

-> trim_trailing_slash(value)
  s = value.to_s
  while s.ends_with?("/")
    s = s.slice(0, s.size() - 1)
  s

-> prerelease_note(version)
  s = version.to_s.strip()
  if s.starts_with?("v")
    s = s.slice(1, s.size() - 1)

  dash = s.index("-")
  if dash != nil
    return s.slice(dash + 1, s.size() - dash - 1)

  parts = s.split(".")
  if parts.size() > 3
    parts[3]
  else
    nil

-> prerelease_rank(note)
  if note == nil || note == ""
    return 3
  if note.starts_with?("alpha")
    return 0
  if note.starts_with?("beta")
    return 1
  if note.starts_with?("rc")
    return 2
  0

-> prerelease_number(note)
  if note == nil || note == ""
    return 0

  if note.starts_with?("alpha")
    tail = note.slice(5, note.size() - 5)
  elsif note.starts_with?("beta")
    tail = note.slice(4, note.size() - 4)
  elsif note.starts_with?("rc")
    tail = note.slice(2, note.size() - 2)
  else
    tail = ""

  if tail == ""
    1
  else
    tail.to_i

-> semver_part(parts, idx)
  if idx < parts.size()
    parts[idx].to_i
  else
    0

-> semver_parts(version)
  s = version.to_s.strip()
  if s.starts_with?("v")
    s = s.slice(1, s.size() - 1)
  dash = s.index("-")
  if dash != nil
    s = s.slice(0, dash)
  parts = s.split(".")
  [semver_part(parts, 0), semver_part(parts, 1), semver_part(parts, 2)]

-> prerelease?(version)
  prerelease_rank(prerelease_note(version)) < 3

-> requirement_allows_prerelease?(requirement)
  req = requirement.to_s
  req.include?(".alpha") || req.include?(".beta") || req.include?(".rc") || req.include?("-alpha") || req.include?("-beta") || req.include?("-rc")

-> semver_compare(left, right)
  a = semver_parts(left)
  b = semver_parts(right)
  i = 0
  while i < 3
    if a[i] < b[i]
      return -1
    if a[i] > b[i]
      return 1
    i += 1

  a_rank = prerelease_rank(prerelease_note(left))
  b_rank = prerelease_rank(prerelease_note(right))
  if a_rank < b_rank
    return -1
  if a_rank > b_rank
    return 1

  a_num = prerelease_number(prerelease_note(left))
  b_num = prerelease_number(prerelease_note(right))
  if a_num < b_num
    return -1
  if a_num > b_num
    return 1
  0

-> semver_upper_for_pessimistic(requirement)
  parts = requirement.to_s.strip().split(".")
  nums = semver_parts(requirement)
  if parts.size() >= 3
    nums[1] = nums[1] + 1
    nums[2] = 0
  else
    nums[0] = nums[0] + 1
    nums[1] = 0
    nums[2] = 0
  nums[0].to_s + "." + nums[1].to_s + "." + nums[2].to_s

-> version_satisfies_single?(version, requirement)
  req = requirement.to_s.strip()
  if req == "" || req == "*" || req == "current" || req == "latest"
    return true

  if req.starts_with?("~>")
    floor = req.slice(2, req.size() - 2).strip()
    ceiling = semver_upper_for_pessimistic(floor)
    return semver_compare(version, floor) >= 0 && semver_compare(version, ceiling) < 0

  if req.starts_with?(">=")
    floor = req.slice(2, req.size() - 2).strip()
    return semver_compare(version, floor) >= 0

  if req.starts_with?(">")
    floor = req.slice(1, req.size() - 1).strip()
    return semver_compare(version, floor) > 0

  if req.starts_with?("<=")
    ceiling = req.slice(2, req.size() - 2).strip()
    return semver_compare(version, ceiling) <= 0

  if req.starts_with?("<")
    ceiling = req.slice(1, req.size() - 1).strip()
    return semver_compare(version, ceiling) < 0

  if req.starts_with?("=")
    exact = req.slice(1, req.size() - 1).strip()
    return semver_compare(version, exact) == 0

  semver_compare(version, req) == 0

-> version_satisfies?(version, requirement)
  req = requirement.to_s.strip()
  if req == ""
    return true

  parts = req.split(",")
  i = 0
  while i < parts.size()
    if !version_satisfies_single?(version, parts[i])
      return false
    i += 1
  true

-> current_epoch
  raw = capture("date +%s 2>/dev/null").strip()
  if raw == ""
    0
  else
    raw.to_i

-> release_security?(bit)
  kind = (bit.release_type || "feature").to_s.downcase()
  kind == "security" || kind == "sec" || kind == "patch-security"

-> release_feature?(bit)
  !release_security?(bit)

-> source_policy_for(bitfile, bit)
  if bit != nil && bit.options != nil
    if bit.options[:trusted] == true
      return SourcePolicy.new(bit.options[:source] || bitfile.source, 0, true)
    if bit.options[:cooldown] != nil
      return SourcePolicy.new(bit.options[:source] || bitfile.source, bit.options[:cooldown].to_i, false)
    if bit.options[:source] != nil
      return bitfile.source_policy(bit.options[:source])
  bitfile.source_policy(bitfile.source)

-> source_url_for(bitfile, bit)
  if bit != nil && bit.options != nil && bit.options[:source] != nil
    return bit.options[:source]
  bitfile.source

-> cooldown_elapsed?(candidate, policy)
  if policy == nil || policy.immediate?()
    return true
  if release_security?(candidate)
    return true
  if candidate.path != nil && !remote_url?(candidate.path)
    return true
  if candidate.published_at == nil || candidate.published_at == ""
    return false

  age = current_epoch() - candidate.published_at.to_i
  age >= policy.cooldown_days.to_i * 86400

-> parse_group_names(raw)
  if raw == nil
    return []

  out = []
  raw.to_s.split(",").each -> (part)
    name = part.strip()
    if name.starts_with?(":")
      name = name.slice(1, name.size() - 1)
    if name != "" && !out.include?(name)
      out.push(name)
  out

-> dependency_groups(dep)
  if dep == nil || dep.options == nil || dep.options[:groups] == nil
    return []
  dep.options[:groups]

-> dependency_selected?(dep, with_groups = [], without_groups = [], deploy = false, explicit = false)
  if dep == nil
    return false
  if explicit
    return true

  groups = dependency_groups(dep)
  if groups.empty?()
    return true

  allowed = {}
  with_groups.each -> (group)
    allowed[group] = true

  blocked = {}
  without_groups.each -> (group)
    blocked[group] = true
  if deploy
    blocked["development"] = true
    blocked["spec"] = true
    blocked["test"] = true

  include = true
  if groups.include?("optional") && allowed["optional"] != true
    include = false

  i = 0
  while i < groups.size()
    group = groups[i]
    if allowed[group] == true
      return true
    if blocked[group] == true
      include = false
    i += 1
  include

-> bitfile_paths_under(root)
  out = capture("find " + shell_quote(root) + " -mindepth 2 -maxdepth 3 -name Bitfile 2>/dev/null | sort")
  if out == nil || out.strip() == ""
    return []
  out.strip().split("\n")

-> installed_bitfiles
  bitfile_paths_under("vendor/bits")

-> bitfiles_to_bits(paths)
  bits = []
  paths.each -> (path)
    bitfile = Tungsten:Bit:Bitfile.load(path)
    if bitfile != nil
      bits.push(bitfile)
  bits

-> installed_bits
  bitfiles_to_bits(installed_bitfiles())

-> installed_bit_named(name)
  bits = installed_bits()
  i = 0
  while i < bits.size()
    if bits[i].name == name
      return bits[i]
    i += 1
  nil

-> insert_bit_by_version(bits, bit)
  inserted = false
  out = []
  i = 0
  while i < bits.size()
    if !inserted && semver_compare(bit.version, bits[i].version) > 0
      out.push(bit)
      inserted = true
    out.push(bits[i])
    i += 1
  if !inserted
    out.push(bit)
  out

-> sorted_bits_by_version(bits)
  out = []
  i = 0
  while i < bits.size()
    out = insert_bit_by_version(out, bits[i])
    i += 1
  out

-> unique_bit_names(bits)
  names = []
  i = 0
  while i < bits.size()
    name = bits[i].name
    if !names.include?(name)
      names.push(name)
    i += 1
  names

-> bits_named(bits, name)
  out = []
  i = 0
  while i < bits.size()
    if bits[i].name == name
      out.push(bits[i])
    i += 1
  sorted_bits_by_version(out)

-> latest_bit(bits)
  sorted = sorted_bits_by_version(bits)
  if sorted.empty?()
    nil
  else
    sorted[0]

-> version_list(bits)
  versions = []
  sorted = sorted_bits_by_version(bits)
  i = 0
  while i < sorted.size()
    versions.push(sorted[i].version)
    i += 1
  versions.join(", ")

-> lock_quote(value)
  "\"" + value.to_s.replace("\"", "\\\"") + "\""

-> config_value(path, key)
  if !File.exists?(path)
    return nil
  parser = Bitfile.new()
  File.read(path).split("\n").each -> (line)
    stripped = line.strip()
    if stripped.starts_with?(key.to_s + " ")
      return parser.quoted(stripped)
  nil

-> config_write(path, pairs)
  ensure_bit_config_home()
  lines = []
  pairs.each -> (key, value)
    if value != nil && value.to_s != ""
      lines.push(key.to_s + " " + lock_quote(value))
  File.write(path, lines.join("\n") + "\n")
  system("chmod 600 " + shell_quote(path) + " 2>/dev/null")

-> prompt_line(message, default = nil, assume_yes = false)
  if assume_yes
    return default
  suffix = if default == nil || default == "" then "" else " [" + default.to_s + "]"
  << message + suffix
  line = ccall("w_read_line_stdin")
  if line == nil
    return default
  text = line.to_s.strip()
  if text == "" && default != nil
    return default
  text

-> confirm_line(message, assume_yes = false)
  if assume_yes
    return true
  << message + " [Y/n]"
  line = ccall("w_read_line_stdin")
  if line == nil
    return true
  text = line.to_s.strip().downcase()
  text == "" || text == "y" || text == "yes"

-> detected_git_email
  value = capture("git config user.email 2>/dev/null").strip()
  if value == ""
    nil
  else
    value

-> detected_git_handle
  value = capture("git config github.user 2>/dev/null").strip()
  if value == ""
    value = capture("git config user.name 2>/dev/null").strip().downcase().replace(" ", "-")
  if value == ""
    nil
  else
    value

-> first_existing_path(paths)
  i = 0
  while i < paths.size()
    if File.exists?(paths[i])
      return paths[i]
    i += 1
  nil

-> default_public_key_path
  home = env("HOME") || "."
  first_existing_path([
    File.join(home, ".ssh/id_ed25519.pub"),
    File.join(home, ".ssh/id_ecdsa.pub"),
    File.join(home, ".ssh/id_rsa.pub")
  ])

-> private_key_for_public_key(path)
  if path == nil
    return nil
  if path.ends_with?(".pub")
    path.slice(0, path.size() - 4)
  else
    path

-> default_signing_key_path
  configured = config_value(bit_profile_path(), "public_key_path")
  key = private_key_for_public_key(configured)
  if key != nil && File.exists?(key)
    return key

  public_key = default_public_key_path()
  key = private_key_for_public_key(public_key)
  if key != nil && File.exists?(key)
    return key
  nil

-> file_sha256(path)
  sum = capture("shasum -a 256 " + shell_quote(path) + " 2>/dev/null | awk '{print $1}'").strip()
  if sum == ""
    sum = capture("sha256sum " + shell_quote(path) + " 2>/dev/null | awk '{print $1}'").strip()
  if sum == ""
    nil
  else
    sum

-> ssh_signature_path(path, private_key)
  if private_key == nil || private_key == "" || !File.exists?(private_key)
    return nil
  system("rm -f " + shell_quote(path + ".sig"))
  ok = system("ssh-keygen -Y sign -f " + shell_quote(private_key) + " -n tungsten-bit -q " + shell_quote(path) + " >/dev/null 2>&1")
  if ok && File.exists?(path + ".sig")
    path + ".sig"
  else
    nil

-> ssh_signature_verify(path, signature, public_key)
  if path == nil || signature == nil || signature == "" || public_key == nil || public_key == ""
    return false

  sig_path = capture("mktemp -t tungsten-bit.sig.XXXXXX").strip()
  allowed_path = capture("mktemp -t tungsten-bit.allowed.XXXXXX").strip()
  if sig_path == "" || allowed_path == ""
    return false

  File.write(sig_path, signature)
  File.write(allowed_path, "tungsten-bit " + public_key.strip() + "\n")
  ok = system("ssh-keygen -Y verify -f " + shell_quote(allowed_path) + " -I tungsten-bit -n tungsten-bit -s " + shell_quote(sig_path) + " < " + shell_quote(path) + " >/dev/null 2>&1")
  system("rm -f " + shell_quote(sig_path) + " " + shell_quote(allowed_path))
  ok

-> has_signature_metadata?(bit)
  (bit.signature != nil && bit.signature != "") || (bit.public_key != nil && bit.public_key != "")

-> compact_one_line(text)
  text.to_s.replace("\n", "\\n")

-> expand_one_line(text)
  text.to_s.replace("\\n", "\n")

+ BitDependency
  ro :name
  ro :version
  ro :options
  ro :path
  ro :summary
  ro :sha256
  ro :signature
  ro :public_key
  ro :security_status
  ro :security_risk
  ro :release_type
  ro :published_at

  -> new(@name, @version = ">= 0.0.0", @options = {}, @path = nil, @summary = "", @sha256 = nil, @signature = nil, @public_key = nil, @security_status = nil, @security_risk = nil, @release_type = nil, @published_at = nil)

  -> source
    if @options != nil && @options[:source] != nil
      @options[:source]
    elsif @path != nil
      "local"
    else
      "unknown"

  -> installed?
    Dir.exists?(install_path)

  -> install_path
    "vendor/bits/" + @name

  -> resolved?(version, path, summary)
    BitDependency.new(@name, version, @options, path, summary, @sha256, @signature, @public_key, @security_status, @security_risk, @release_type, @published_at)

+ SourcePolicy
  ro :url
  ro :cooldown_days
  ro :trusted

  -> new(@url, @cooldown_days = 0, @trusted = false)

  -> immediate?
    @trusted == true || @cooldown_days.to_i <= 0

+ BitExecutable
  ro :name
  ro :source

  -> new(@name, @source)

+ Bitfile
  ro :name
  ro :version
  ro :summary
  ro :license
  ro :source
  ro :source_policies
  ro :tungsten_requirement
  ro :dependencies
  ro :executables
  ro :assets
  ro :path

  -> new(name = "unknown", version = "0.0.0", summary = "", license = "", source = nil, dependencies = nil, path = nil, tungsten_requirement = nil, executables = nil, assets = nil)
    @name = name
    @version = version
    @summary = summary
    @license = license
    @source = source || default_bit_source()
    @source_policies = {}
    @source_policies[@source] = SourcePolicy.new(@source, 0, false)
    @tungsten_requirement = tungsten_requirement
    @dependencies = dependencies || []
    @executables = executables || []
    @assets = assets || []
    @path = path
    @group_stack = []

  -> .load(path)
    if !File.exists?(path)
      return nil
    Bitfile.parse(File.read(path), path)

  -> .parse(content, path = nil)
    bitfile = Bitfile.new()
    bitfile.set_path(path)
    lines = content.split("\n")
    lines.each -> (line)
      bitfile.apply_line(line)
    bitfile.infer_name_from_path()
    bitfile

  -> set_path(path)
    @path = path

  -> source_policy(url = nil)
    key = url || @source
    @source_policies[key] || SourcePolicy.new(key, 0, false)

  -> set_source_policy(url, cooldown_days = 0, trusted = false)
    if url != nil
      @source_policies[url] = SourcePolicy.new(url, cooldown_days.to_i, trusted)

  -> dir
    if @path != nil && @path.ends_with?("/Bitfile")
      return @path.slice(0, @path.size() - 8)
    "."

  -> infer_name_from_path
    if @name == "unknown" && @path != nil
      @name = dir().split("/").last()

  -> current_groups
    groups = []
    i = 0
    while i < @group_stack.size()
      groups.push(@group_stack[i])
      i += 1
    groups

  -> quoted(line)
    first = line.index("\"")
    if first == nil
      return nil
    rest = line.slice(first + 1, line.size() - first - 1)
    second = rest.index("\"")
    if second == nil
      return nil
    rest.slice(0, second)

  -> second_quoted(line)
    first = line.index("\"")
    if first == nil
      return nil
    rest = line.slice(first + 1, line.size() - first - 1)
    second = rest.index("\"")
    if second == nil
      return nil
    tail = rest.slice(second + 1, rest.size() - second - 1)
    quoted(tail)

  -> option_value(line, name)
    marker = name + ":"
    pos = line.index(marker)
    if pos == nil
      return nil

    tail = line.slice(pos + marker.size(), line.size() - pos - marker.size()).strip()
    if tail.starts_with?("\"")
      return quoted(tail)

    comma = tail.index(",")
    if comma != nil
      tail = tail.slice(0, comma)
    tail.strip()

  -> option_bool(line, name)
    option_value(line, name) == "true"

  -> option_symbol(line, name)
    value = option_value(line, name)
    if value == nil
      return nil
    if value.starts_with?(":")
      return value.slice(1, value.size() - 1)
    value

  -> group_name_from_line(line)
    tail = line.slice(6, line.size() - 6).strip()
    if tail.starts_with?(":")
      tail = tail.slice(1, tail.size() - 1)
    tail.split(" ").first()

  -> parse_tungsten_name(value)
    if value == nil || @name != "unknown"
      return nil

    parts = value.split("-")
    suffix = parts.last()
    if suffix != nil && suffix.split(".").size() == 3
      @name = value.slice(0, value.size() - suffix.size() - 1)
      if @version == "0.0.0"
        @version = suffix
    else
      @name = value

  -> apply_line(raw)
    line = raw.strip()
    if line == "" || line.starts_with?("#")
      return nil

    if line.starts_with?("group ")
      group_name = group_name_from_line(line)
      if group_name != nil && group_name != ""
        @group_stack.push(group_name)
      return nil

    if line == "end"
      if !@group_stack.empty?()
        @group_stack.pop()
      return nil

    value = quoted(line)
    if line.starts_with?("source ")
      if value
        @source = value
        set_source_policy(value, option_value(line, "cooldown") || option_value(line, "cooldown_days") || 0, option_bool(line, "trusted"))
    elsif line.starts_with?("name ")
      @name = value if value
    elsif line.starts_with?("version ")
      @version = value if value
    elsif line.starts_with?("summary ")
      @summary = value if value
    elsif line.starts_with?("license ")
      @license = value if value
    elsif line.starts_with?("tungsten ")
      @tungsten_requirement = value if value
    elsif line.starts_with?("executable ")
      executable_name = value
      if executable_name != nil
        executable_source = option_value(line, "source")
        if executable_source == nil || executable_source == ""
          executable_source = "lib/" + executable_name + ".w"
        @executables.push(BitExecutable.new(executable_name, executable_source))
    elsif line.starts_with?("asset ")
      append_unique(@assets, value) if value
    elsif line.starts_with?("bit ") || line.starts_with?("dependency ")
      dep_name = value
      dep_version = second_quoted(line)
      if dep_version == nil
        dep_version = ">= 0.0.0"
      if dep_name != nil
        dep_path = option_value(line, "path")
        if dep_path != nil && @path != nil && !dep_path.starts_with?("/")
          dep_path = File.join(dir, dep_path)
        dep_source = option_value(line, "source")
        dep_git = option_value(line, "git") || option_value(line, "github")
        dep_groups = current_groups()
        inline_group = option_symbol(line, "group")
        if inline_group != nil && !dep_groups.include?(inline_group)
          dep_groups.push(inline_group)
        if option_bool(line, "optional") && !dep_groups.include?("optional")
          dep_groups.push("optional")
        dep_options = {groups: dep_groups}
        if dep_source != nil
          dep_options[:source] = dep_source
        if dep_git != nil
          dep_options[:git] = dep_git
        if option_bool(line, "trusted")
          dep_options[:trusted] = true
        if option_value(line, "cooldown") != nil
          dep_options[:cooldown] = option_value(line, "cooldown")
        @dependencies.push(BitDependency.new(dep_name, dep_version, dep_options, dep_path))

  -> find_dependency(name)
    needle = name.to_s
    @dependencies.each -> (dep)
      if dep.name == needle
        return dep
    nil

+ Lockfile
  ro :dependencies

  -> new(@dependencies = [])

  -> .load(path)
    if File.exists?(path)
      Lockfile.parse(File.read(path))
    else
      Lockfile.empty

  -> .empty
    Lockfile.new([])

  -> .parse(content)
    lockfile = Lockfile.new([])
    content.split("\n").each -> (line)
      stripped = line.strip()
      if stripped == "" || stripped.starts_with?("#")
        next

      if stripped.starts_with?("bit ") || stripped.starts_with?("dependency ")
        parser = Bitfile.new()
        dep_name = parser.quoted(stripped)
        dep_version = parser.second_quoted(stripped)
        dep_path = parser.option_value(stripped, "path")
        dep_source = parser.option_value(stripped, "source")
        dep_summary = parser.option_value(stripped, "summary")
        dep_sha256 = parser.option_value(stripped, "sha256")
        dep_signature = parser.option_value(stripped, "signature")
        dep_public_key = parser.option_value(stripped, "public_key")
        dep_security_status = parser.option_value(stripped, "security_status")
        dep_security_risk = parser.option_value(stripped, "security_risk")
        dep_release_type = parser.option_value(stripped, "release_type")
        dep_published_at = parser.option_value(stripped, "published_at")
        if dep_source == nil
          if dep_path == nil
            dep_source = "unknown"
          else
            dep_source = "local"
        if dep_version == nil
          dep_version = ">= 0.0.0"
        if dep_summary == nil
          dep_summary = ""
        if dep_name != nil
          lockfile.dependencies.push(BitDependency.new(dep_name, dep_version, {source: dep_source}, dep_path, dep_summary, dep_sha256, expand_one_line(dep_signature || ""), expand_one_line(dep_public_key || ""), dep_security_status, dep_security_risk, dep_release_type, dep_published_at))
      else
        parts = stripped.split(" ")
        if parts.size() >= 2
          lockfile.dependencies.push(BitDependency.new(parts[0], parts[1]))
    lockfile

  -> .generate(resolution)
    lines = []
    resolution.each -> (bit)
      line = "bit " + lock_quote(bit.name) + ", " + lock_quote(bit.version) + ", source: " + lock_quote(bit.source)
      if bit.path != nil
        line = line + ", path: " + lock_quote(bit.path)
      if bit.summary != nil && bit.summary != ""
        line = line + ", summary: " + lock_quote(bit.summary)
      if bit.sha256 != nil && bit.sha256 != ""
        line = line + ", sha256: " + lock_quote(bit.sha256)
      if bit.signature != nil && bit.signature != ""
        line = line + ", signature: " + lock_quote(compact_one_line(bit.signature))
      if bit.public_key != nil && bit.public_key != ""
        line = line + ", public_key: " + lock_quote(compact_one_line(bit.public_key))
      if bit.security_status != nil && bit.security_status != ""
        line = line + ", security_status: " + lock_quote(bit.security_status)
      if bit.security_risk != nil && bit.security_risk != ""
        line = line + ", security_risk: " + lock_quote(bit.security_risk)
      if bit.release_type != nil && bit.release_type != ""
        line = line + ", release_type: " + lock_quote(bit.release_type)
      if bit.published_at != nil && bit.published_at != ""
        line = line + ", published_at: " + lock_quote(bit.published_at)
      lines.push(line)
    lines.join("\n")

  -> find_dependency(name)
    needle = name.to_s
    @dependencies.each -> (dep)
      if dep.name == needle
        return dep
    nil

+ Resolver
  -> new(@bitfile, @lockfile, @allow_prerelease = false)

  -> resolve(bits)
    # BFS: top-level Bitfile deps, then each resolved bit's own Bitfile deps.
    resolved = []
    seen = {}
    if bits == nil
      return resolved
    queue = []
    bits.each -> (bit)
      if bit != nil
        queue.push(bit)
    qi = 0
    while qi < queue.size()
      bit = queue[qi]
      qi += 1
      if bit == nil || seen[bit.name] == true
        next
      seen[bit.name] = true
      one = resolve_one(bit)
      resolved.push(one)
      # Transitive: load the installed/source Bitfile and enqueue its deps.
      child_path = one.path
      if child_path != nil && child_path != ""
        bf_path = nil
        if child_path.ends_with?("Bitfile") && file?(child_path)
          bf_path = child_path
        elsif file?(child_path + "/Bitfile")
          bf_path = child_path + "/Bitfile"
        if bf_path != nil
          begin
            child_bf = Bitfile.load(bf_path)
            if child_bf != nil && child_bf.dependencies != nil
              child_bf.dependencies.each -> (dep)
                if dep != nil && seen[dep.name] != true
                  queue.push(dep)
          rescue err
            # Missing or unreadable nested Bitfile — skip transitive for that node
            nil
    resolved

  -> resolve_one(bit)
    locked = @lockfile.find_dependency(bit.name)
    requested = bit.version
    version = requested
    local = nil
    policy = source_policy_for(@bitfile, bit)
    source_url = source_url_for(@bitfile, bit)

    if locked != nil && version_satisfies?(locked.version, requested)
      if locked.path != nil && Dir.exists?(locked.path)
        local = locked
      if local == nil
        local = find_allowed(bit.name, "= " + locked.version, true, policy, source_url)
      if local != nil
        version = locked.version

    path = bit.path
    summary = bit.summary
    if path == nil
      if local == nil
        local = find_allowed(bit.name, requested, @allow_prerelease, policy, source_url)
      if local != nil
        path = local.path
        summary = local.summary
        version = local.version

    if local != nil
      return BitDependency.new(bit.name, version, local.options, path, summary, local.sha256, local.signature, local.public_key, local.security_status, local.security_risk, local.release_type, local.published_at)
    bit.resolved?(version, path, summary)

  -> find_allowed(name, requirement, allow_prerelease, policy, source_url)
    client = Registry:Client.new(source_url)
    results = client.versions(name, allow_prerelease)
    results.each -> (candidate)
      if version_satisfies?(candidate.version, requirement) && cooldown_elapsed?(candidate, policy)
        return candidate
    nil

+ WorkerPool
  -> new(@jobs = 1)
    @queue = []

  -> enqueue(&block)
    @queue.push(block)

  -> run
    @queue.each -> (job)
      job.call()

  -> wait
    true

+ BitInstaller
  -> new(@bit, @options = {})

  -> install
    if @bit.path == nil
      return false

    FileUtils.mkdir_p("vendor/bits")
    dest = @bit.install_path
    if Dir.exists?(dest)
      return true

    if remote_url?(@bit.path)
      FileUtils.mkdir_p(dest)
      tmp = capture("mktemp -t tungsten-bit.XXXXXX").strip()
      ok = system("curl -fsSL -o " + shell_quote(tmp) + " " + shell_quote(@bit.path))
      if !ok
        FileUtils.rm_rf(dest)
        return false
      if @bit.sha256 != nil && @bit.sha256 != "" && file_sha256(tmp) != @bit.sha256
        FileUtils.rm_rf(dest)
        system("rm -f " + shell_quote(tmp))
        return false
      if has_signature_metadata?(@bit) && !ssh_signature_verify(tmp, @bit.signature, @bit.public_key)
        FileUtils.rm_rf(dest)
        system("rm -f " + shell_quote(tmp))
        return false
      ok = system("tar -xf " + shell_quote(tmp) + " -C " + shell_quote(dest))
      system("rm -f " + shell_quote(tmp))
      if !ok
        FileUtils.rm_rf(dest)
        return false
      return File.exists?(File.join(dest, "Bitfile"))

    FileUtils.cp_r(@bit.path, dest)
    Dir.exists?(dest)

+ BuildConfig
  ro :output
  ro :release
  ro :target
  ro :jobs

  -> new(output: "build", release: false, target: "native", jobs: 1)
    @output = output
    @release = release
    @target = target
    @jobs = jobs

  -> output_path
    File.join(@output, "bit")

+ Dependencies
  -> .satisfied?(bitfile)
    true

+ Compiler
  ro :elapsed
  ro :command

  -> new(@config)
    @started = clock()
    @compiled = []
    @command = tungsten_compiler_command()
    FileUtils.mkdir_p(@config.output)

  -> available?
    @command != nil && @command != ""

  -> compile(source, output = nil)
    if !available?
      return false

    out = output
    if out == nil
      name = source.split("/").last
      out = File.join(@config.output, name.replace(".w", ""))
    FileUtils.mkdir_p(path_parent(out))
    @compiled.push(out)
    command = shell_quote(@command) + " compile " + shell_quote(source) + " --out " + shell_quote(out)
    if @config.release
      command = command + " --release"
    system(command)

  -> link
    @elapsed = ((clock() - @started) * 1000).to_i
    true

+ Archive
  ro :path
  ro :size_human
  ro :name
  ro :version
  ro :sha256
  ro :signature
  ro :public_key

  -> new(@path, @size_human = "0B", @name = nil, @version = nil, @sha256 = nil, @signature = nil, @public_key = nil)

+ RegistryResponse
  ro :status
  ro :message

  -> new(@status, @message = "")

+ Packager
  -> new(@bitfile)

  -> pack
    FileUtils.mkdir_p("pkg")
    path = "pkg/" + @bitfile.name + "-" + @bitfile.version + ".bit"
    members = ["Bitfile"]
    conventional_files = [
      "README.md", "README.txt",
      "LICENSE", "LICENSE.md", "LICENSE.txt",
      "LICENSE-MIT", "LICENSE-MIT.md", "LICENSE-MIT.txt",
      "LICENSE-APACHE", "LICENSE-APACHE.md", "LICENSE-APACHE.txt",
      "LICENSE-APACHE-2.0", "LICENSE-APACHE-2.0.md", "LICENSE-APACHE-2.0.txt",
      "COPYING", "COPYING.LESSER",
      "NOTICE", "NOTICE.md", "NOTICE.txt",
      "THIRD_PARTY", "THIRD_PARTY.md", "THIRD_PARTY.txt",
      "COPYRIGHT", "COPYRIGHT.md", "COPYRIGHT.txt"
    ]
    conventional_files.each -> (member)
      append_unique(members, member) if File.exists?(member)

    append_unique(members, "lib") if Dir.exists?("lib")
    append_unique(members, "spec") if Dir.exists?("spec")

    @bitfile.executables.each -> (executable)
      source = executable.source
      if !source.starts_with?("lib/") && source != "lib"
        unless safe_package_path?(source)
          <! "Executable source must be a package-relative path: " + source.to_s
        unless File.exists?(source)
          <! "Executable source not found: " + source.to_s
        append_unique(members, source)

    packaged_asset_paths(@bitfile).each -> (asset)
      unless safe_package_path?(asset)
        <! "Asset must be a package-relative path: " + asset.to_s
      unless File.exists?(asset)
        <! "Declared asset not found: " + asset.to_s
      append_unique(members, asset)

    cmd = "tar -cf " + shell_quote(path)
    i = 0
    while i < members.size()
      cmd = cmd + " " + shell_quote(members[i])
      i += 1
    ok = system(cmd)
    if !ok
      <! "Failed to pack " + path
    Archive.new(path, file_size_human(path), @bitfile.name, @bitfile.version, file_sha256(path), nil, nil)

+ AuthState
  ro :token

  -> new(@token = nil)

  -> valid?
    @token != nil && @token != ""

  -> header
    "Authorization: Bearer " + @token

  -> registry
    config_value(bit_profile_path(), "registry") || DEFAULT_REGISTRY

  -> handle
    config_value(bit_profile_path(), "handle")

  -> email
    config_value(bit_profile_path(), "email")

  -> public_key_path
    config_value(bit_profile_path(), "public_key_path")

  -> public_key
    config_value(bit_profile_path(), "public_key")

+ Auth
  -> .load
    profile = bit_profile_path()
    credentials = bit_credentials_path()
    token = env("BIT_TOKEN")
    if token == nil || token == ""
      token = env("TUNGSTEN_BITS_TOKEN")
    if token == nil || token == ""
      token = env("TUNGSTEN_BIT_TOKEN")
    if token == nil || token == ""
      token = config_value(credentials, "token")

    AuthState.new(token)

  -> .save_profile(handle, email, public_key_path, public_key, registry = DEFAULT_REGISTRY)
    config_write(bit_profile_path(), {
      registry: registry,
      handle: handle,
      email: email,
      public_key_path: public_key_path,
      public_key: public_key
    })

  -> .save_token(token, registry = DEFAULT_REGISTRY)
    config_write(bit_credentials_path(), {
      registry: registry,
      token: token
    })

+ Registry:Client
  -> new(@url, @auth = nil)

  -> remote?
    remote_url?(@url)

  -> endpoint(path)
    trim_trailing_slash(@url) + path

  -> remote_get(command_path)
    capture("curl -fsSL " + shell_quote(endpoint(command_path)) + " 2>/dev/null")

  -> remote_get_query(command_path, query)
    capture("curl -fsSL --get " + shell_quote(endpoint(command_path)) + " " + query + " 2>/dev/null")

  -> parse_registry_lines(text)
    if text == nil || text.strip() == ""
      return []
    Tungsten:Bit:Lockfile.parse(text).dependencies

  -> parse_response_value(text, key)
    if text == nil
      return nil
    parser = Tungsten:Bit:Bitfile.new()
    text.split("\n").each -> (line)
      stripped = line.strip()
      if stripped.starts_with?(key.to_s + " ")
        return parser.quoted(stripped)
    nil

  -> post_form(command_path, fields)
    cmd = "curl -fsS -X POST "
    fields.each -> (key, value)
      if value != nil && value.to_s != ""
        cmd = cmd + "-F " + shell_quote(key.to_s + "=" + value.to_s) + " "
    cmd = cmd + shell_quote(endpoint(command_path)) + " 2>/dev/null"
    capture(cmd)

  -> signup(handle, email, password, public_key, github_email = nil)
    return Tungsten:Bit:RegistryResponse.new(:error, "remote registry required") unless remote?
    text = post_form("/api/v1/accounts", {
      handle: handle,
      email: email,
      password: password,
      public_key: public_key,
      github_email: github_email
    })
    token = parse_response_value(text, "token")
    if token != nil && token != ""
      return Tungsten:Bit:RegistryResponse.new(:ok, token)
    Tungsten:Bit:RegistryResponse.new(:error, "signup failed")

  -> login(handle_or_email, password)
    return Tungsten:Bit:RegistryResponse.new(:error, "remote registry required") unless remote?
    text = post_form("/api/v1/sessions", {
      handle: handle_or_email,
      password: password
    })
    token = parse_response_value(text, "token")
    if token != nil && token != ""
      return Tungsten:Bit:RegistryResponse.new(:ok, token)
    Tungsten:Bit:RegistryResponse.new(:error, "login failed")

  -> version_exists?(name, version)
    found = find(name, "= " + version.to_s, true)
    found != nil

  -> yank(name, version)
    return Tungsten:Bit:RegistryResponse.new(:error, "remote registry required") unless remote?
    unless @auth != nil && @auth.valid?
      return Tungsten:Bit:RegistryResponse.new(:error, "missing registry token")
    cmd = "curl -fsS -X DELETE "
    cmd = cmd + "-H " + shell_quote(@auth.header) + " "
    cmd = cmd + shell_quote(endpoint("/api/v1/bits/" + name.to_s + "/versions/" + version.to_s + "/yank")) + " 2>/dev/null"
    ok = system(cmd)
    if ok
      Tungsten:Bit:RegistryResponse.new(:ok, "")
    else
      Tungsten:Bit:RegistryResponse.new(:error, "yank failed")

  -> search(query, limit = 25, sort = "relevance")
    if remote?
      q = " --data-urlencode " + shell_quote("q=" + query.to_s)
      q = q + " --data-urlencode " + shell_quote("limit=" + limit.to_s)
      q = q + " --data-urlencode " + shell_quote("sort=" + sort.to_s)
      return parse_registry_lines(remote_get_query("/api/v1/registry/search", q))

    needle = query.to_s.downcase()
    max = limit.to_i
    if max <= 0
      max = 25

    results = []
    local_bitfiles.each -> (path)
      bitfile = Tungsten:Bit:Bitfile.load(path)
      if bitfile != nil
        haystack = (bitfile.name + " " + bitfile.summary).downcase()
        if needle == "" || haystack.include?(needle)
          results.push(Tungsten:Bit:BitDependency.new(bitfile.name, bitfile.version, {}, bitfile.dir, bitfile.summary))

    limited = []
    results.each -> (bit)
      if limited.size() < max
        limited.push(bit)
    limited

  -> versions(name, allow_prerelease = true)
    if remote?
      q = " --data-urlencode " + shell_quote("pre=" + allow_prerelease.to_s)
      path = "/api/v1/registry/bits/" + name.to_s + "/versions"
      return sorted_bits_by_version(parse_registry_lines(remote_get_query(path, q)))

    results = []
    paths = local_bitfiles()
    i = 0
    while i < paths.size()
      path = paths[i]
      bitfile = Tungsten:Bit:Bitfile.load(path)
      if bitfile != nil && bitfile.name == name
        if allow_prerelease || !prerelease?(bitfile.version)
          results.push(Tungsten:Bit:BitDependency.new(bitfile.name, bitfile.version, {}, bitfile.dir, bitfile.summary))
      i += 1
    sorted_bits_by_version(results)

  -> find(name, requirement = ">= 0.0.0", allow_prerelease = false)
    if remote?
      results = versions(name, allow_prerelease)
      results.each -> (bit)
        if version_satisfies?(bit.version, requirement)
          return bit
      return nil

    best = nil
    paths = local_bitfiles()
    i = 0
    while i < paths.size()
      path = paths[i]
      bitfile = Tungsten:Bit:Bitfile.load(path)
      if bitfile != nil && bitfile.name == name && version_satisfies?(bitfile.version, requirement)
        if !allow_prerelease && prerelease?(bitfile.version) && !requirement_allows_prerelease?(requirement)
          i += 1
          next
        bit = Tungsten:Bit:BitDependency.new(bitfile.name, bitfile.version, {}, bitfile.dir, bitfile.summary)
        if best == nil || semver_compare(bit.version, best.version) > 0
          best = bit
      i += 1
    best

  # Scan a local directory registry. Prefer the client URL when it is a
  # filesystem path (Bitfile `source "/path"` or BIT_HOME); otherwise
  # fall back to $BIT_HOME / "bits".
  -> local_registry_root
    if @url != nil && @url != "" && !remote_url?(@url)
      u = "" + @url
      if u.starts_with?("file://")
        u = u.slice(7, u.size() - 7)
      return u
    bit_home()

  -> local_bitfiles
    bitfile_paths_under(local_registry_root())

  -> push(archive, tag: "latest", otp: nil, release_type: "feature")
    if @url.starts_with?("file://")
      dest = @url.slice(7, @url.size() - 7)
    elsif @url.starts_with?("/")
      dest = @url
    else
      unless remote?
        return Tungsten:Bit:RegistryResponse.new(:error, "unsupported registry URL")
      unless @auth != nil && @auth.valid?
        return Tungsten:Bit:RegistryResponse.new(:error, "missing registry token")

      cmd = "curl -fsS -X POST "
      cmd = cmd + "-H " + shell_quote(@auth.header) + " "
      cmd = cmd + "-F " + shell_quote("name=" + archive.name.to_s) + " "
      cmd = cmd + "-F " + shell_quote("version=" + archive.version.to_s) + " "
      cmd = cmd + "-F " + shell_quote("tag=" + tag.to_s) + " "
      cmd = cmd + "-F " + shell_quote("release_type=" + release_type.to_s) + " "
      cmd = cmd + "-F " + shell_quote("sha256=" + archive.sha256.to_s) + " "
      if archive.signature != nil
        cmd = cmd + "-F " + shell_quote("signature=" + archive.signature.to_s) + " "
      if archive.public_key != nil
        cmd = cmd + "-F " + shell_quote("public_key=" + archive.public_key.to_s) + " "
      if otp != nil
        cmd = cmd + "-F " + shell_quote("otp=" + otp.to_s) + " "
      cmd = cmd + "-F " + shell_quote("archive=@" + archive.path) + " "
      cmd = cmd + shell_quote(endpoint("/api/v1/bits"))
      ok = system(cmd)
      if ok
        return Tungsten:Bit:RegistryResponse.new(:ok, "")
      return Tungsten:Bit:RegistryResponse.new(:error, "remote registry rejected the publish")

    Tungsten:Bit:FileUtils.mkdir_p(dest)
    ok = system("cp " + shell_quote(archive.path) + " " + shell_quote(dest + "/"))
    if ok && archive.sha256 != nil
      File.write(dest + "/" + archive.name.to_s + "-" + archive.version.to_s + ".sha256", archive.sha256 + "\n")
    if ok && archive.signature != nil
      File.write(dest + "/" + archive.name.to_s + "-" + archive.version.to_s + ".sig", archive.signature)
    if ok
      Tungsten:Bit:RegistryResponse.new(:ok, "")
    else
      Tungsten:Bit:RegistryResponse.new(:error, "could not copy archive into registry")

+ JSON
  -> .encode(value)
    value.to_s
