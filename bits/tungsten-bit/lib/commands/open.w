<<~ CLI

  USAGE
    bit open NAME [options]

  OPTIONS
    -e, --editor  EDITOR  # Open bit in EDITOR
    -v, --version VERSION # Open bit at VERSION

  DEFAULTS
    -e [env_editor]

+ Open ->

  -> env_editor
    ENV.first(:BIT_EDITOR, :VISUAL, :EDITOR, 'vi')
