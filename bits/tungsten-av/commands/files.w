use ../lib/cli

in Av:Commands

+ Files < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Print the native AV source files for this toolchain"

  -> usage
    "bit av files \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    CLI.new(@raw_args, "files").files

Av:CLI.run(Av:Commands:Files, argv())
