# bit sign — sign the current bit archive with an SSH signing key
in Tungsten:Bit:Commands

+ Sign < Command
  -> summary
    "Sign the current bit archive"

  -> usage
    "USAGE\n  bit sign (options)\n\nOPTIONS\n      --key PATH       SSH private key to sign with\n      --archive PATH   Existing archive to sign\n      --unsigned       Only write SHA256 metadata\n"

  -> execute
    bitfile = Bitfile.load("Bitfile")
    abort "No Bitfile found" unless bitfile

    archive_path = option(:archive)
    archive = if archive_path == nil
      Packager.new(bitfile).pack
    else
      Archive.new(archive_path, file_size_human(archive_path), bitfile.name, bitfile.version, file_sha256(archive_path))

    sha = file_sha256(archive.path)
    abort "Could not compute sha256 for " + archive.path unless sha
    File.write(archive.path + ".sha256", sha + "  " + archive.path + "\n")
    say "sha256 " + sha

    if flag?(:unsigned)
      say "Unsigned metadata written for " + archive.path
      return

    key = option(:key) || default_signing_key_path()
    abort "No signing key found. Pass --key PATH or run `bit create` to choose a public key." unless key

    sig_path = ssh_signature_path(archive.path, key)
    abort "Could not sign " + archive.path + " with " + key unless sig_path
    say "signed " + sig_path
