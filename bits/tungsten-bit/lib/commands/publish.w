# bit publish — publish a bit to the registry
in Tungsten:Bit:Commands

+ Publish < Command
  -> summary
    "Publish a bit to bits.tungsten-lang.org"

  -> usage
    "USAGE\n  bit publish (options)\n\nOPTIONS\n      --registry URL    Registry to publish to\n      --tag TAG         Tag the release\n      --dry-run         Validate without publishing\n      --skip-ci         Skip the Tungsten release CI grid\n      --ci-command CMD  CI command for each Tungsten release\n      --tungsten LIST   Comma-separated Tungsten release labels\n      --release-type TYPE  feature or security\n      --security       Mark this as a security release\n      --key PATH        SSH private key used for signing\n      --unsigned        Allow an unsigned archive\n      --otp CODE        One-time password for 2FA\n"

  -> execute
    bitfile = Bitfile.load("Bitfile")
    abort "No Bitfile found" unless bitfile

    registry = option(:registry, DEFAULT_REGISTRY)
    auth = Auth.load
    client = Tungsten:Bit:Registry:Client.new(registry, auth)

    say "Publishing " + bitfile.name + " " + bitfile.version + "..."

    errors = validate(bitfile)
    if errors.any?
      say "Validation errors:"
      errors.each -> (e)
        say "  - " + e.to_s
      abort "Fix validation errors before publishing"

    verify_version_tick(bitfile, client) unless flag?(:dry_run)
    run_ci_grid(bitfile) unless flag?(:dry_run)

    archive = Packager.new(bitfile).pack
    archive = signed_archive(archive)
    verbose("  packed  " + archive.path + " (" + archive.size_human + ")")
    verbose("  sha256  " + archive.sha256.to_s)

    if flag?(:dry_run)
      say "Dry run - would publish " + bitfile.name + " " + bitfile.version
      return

    abort "Not logged in. Run `bit register` or `bit login`." unless auth.valid?

    response = client.push(archive, tag: option(:tag, "latest"), otp: option(:otp), release_type: release_type())

    case response.status
      :ok      => say "Published " + bitfile.name + " " + bitfile.version + " to " + registry
      :conflict => abort "Version " + bitfile.version + " already exists. Bump your version."
      =>          abort "Publish failed: " + response.message

  -> release_type
    if flag?(:security)
      return "security"
    value = option(:release_type, "feature").to_s.downcase()
    if value == "security" || value == "feature"
      value
    else
      abort "Release type must be feature or security"

  -> validate(bitfile)
    errors = []
    errors.push("Missing name")    unless bitfile.name
    errors.push("Missing version") unless bitfile.version
    errors.push("Missing summary") unless bitfile.summary
    errors.push("Missing license") unless bitfile.license
    errors.push("No lib/ directory found") unless Dir.exists?("lib")
    errors

  -> verify_version_tick(bitfile, client)
    if client.version_exists?(bitfile.name, bitfile.version)
      abort "Version " + bitfile.version + " already exists. Bump the version, or run `bit yank " + bitfile.name + " " + bitfile.version + "` if this release must be removed."

    latest = client.find(bitfile.name, ">= 0.0.0", true)
    if latest != nil && semver_compare(bitfile.version, latest.version) <= 0
      abort "Version must be ticked forward. Latest published version is " + latest.version + "; current Bitfile is " + bitfile.version + "."

  -> signed_archive(archive)
    sha = file_sha256(archive.path)
    abort "Could not compute sha256 for " + archive.path unless sha
    File.write(archive.path + ".sha256", sha + "  " + archive.path + "\n")

    if flag?(:unsigned)
      return Archive.new(archive.path, archive.size_human, archive.name, archive.version, sha, nil, nil)

    key = option(:key) || default_signing_key_path()
    if key == nil && flag?(:dry_run)
      return Archive.new(archive.path, archive.size_human, archive.name, archive.version, sha, nil, nil)
    abort "No signing key found. Pass --key PATH, run `bit create`, or use --unsigned." unless key
    sig_path = ssh_signature_path(archive.path, key)
    abort "Could not sign " + archive.path + " with " + key unless sig_path
    public_key_path = key + ".pub"
    public_key = if File.exists?(public_key_path) then File.read(public_key_path).strip() else nil
    Archive.new(archive.path, archive.size_human, archive.name, archive.version, sha, File.read(sig_path), public_key)

  -> ci_versions(bitfile)
    raw = option(:tungsten) || env("BIT_CI_TUNGSTEN") || env("TUNGSTEN_CI_RELEASES")
    if raw != nil && raw.strip() != ""
      return raw.split(",")

    if File.exists?(".tungsten/releases")
      lines = []
      File.read(".tungsten/releases").split("\n").each -> (line)
        stripped = line.strip()
        if stripped != "" && !stripped.starts_with?("#")
          lines.push(stripped)
      if !lines.empty?()
        return lines

    if bitfile.tungsten_requirement != nil
      [bitfile.tungsten_requirement]
    else
      ["current"]

  -> run_ci_grid(bitfile)
    if flag?(:skip_ci)
      return nil
    ci_command = option(:ci_command, "bit spec")
    versions = ci_versions(bitfile)
    versions.each -> (version)
      label = version.to_s.strip()
      if label != ""
        say "CI " + label + ": " + ci_command
        ok = system("TUNGSTEN_VERSION=" + shell_quote(label) + " " + ci_command)
        unless ok
          abort "CI failed for Tungsten " + label
