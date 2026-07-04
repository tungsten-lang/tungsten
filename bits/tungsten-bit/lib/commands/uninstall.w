<<~ CLI

  USAGE
    bit uninstall NAME [NAME…] [options]

  OPTIONS
    -a, --[no-]all        # Uninstall all versions
    -f, --[no-]force      # Uninstall all versions, ignoring dependencies
    -i, --install-dir DIR # Directory where bit is installed
    -v, --version VERSION # Version of the bit to uninstall

  SUMMARY
    Uninstall bits from the local repository

  DESCRIPTION
    Uninstalls a previously installed bit.

    Bit will ask for confirmation if you are attempting to uninstall a bit
    that is a dependency of an existing bit. You can use the --force
    option to skip this check.

    DEFAULTS
      --version '>= 0' --no-force

+ Uninstall ->
