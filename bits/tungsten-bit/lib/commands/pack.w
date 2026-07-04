# bit pack — build a .bit archive without uploading it
in Tungsten:Bit:Commands

+ Pack < Command
  -> summary
    "Pack the current bit into pkg/NAME-VERSION.bit"

  -> usage
    "USAGE\n  bit pack (options)\n\nOPTIONS\n      --sign       Sign after packing\n      --key PATH   SSH private key for signing\n"

  -> execute
    bitfile = Bitfile.load("Bitfile")
    abort "No Bitfile found" unless bitfile
    archive = Packager.new(bitfile).pack
    sha = file_sha256(archive.path)
    if sha != nil
      File.write(archive.path + ".sha256", sha + "  " + archive.path + "\n")
    say "packed " + archive.path + " (" + archive.size_human + ")"
    if sha != nil
      say "sha256 " + sha

    if flag?(:sign)
      key = option(:key) || default_signing_key_path()
      abort "No signing key found. Pass --key PATH or run `bit create`." unless key
      sig_path = ssh_signature_path(archive.path, key)
      abort "Could not sign " + archive.path unless sig_path
      say "signed " + sig_path
