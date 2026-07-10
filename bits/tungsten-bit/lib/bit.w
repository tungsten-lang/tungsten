# Tungsten Bit — the package manager for Tungsten
# Main entry point that loads all components and dispatches commands

in Tungsten:Bit

use command
use version
use support
use commands

# Command registry — maps command names to their handler classes.
# Handler classes live in the Tungsten:Bit:Commands namespace; this
# top-level table references them with their fully-qualified names
# (top-level code has no enclosing namespace to resolve bare names
# against, unlike the command bodies themselves).
commands = {
  install:   Tungsten:Bit:Commands:Install,
  new:       Tungsten:Bit:Commands:New,
  build:     Tungsten:Bit:Commands:Build,
  spec:      Tungsten:Bit:Commands:Spec,
  publish:   Tungsten:Bit:Commands:Publish,
  push:      Tungsten:Bit:Commands:Push,
  sign:      Tungsten:Bit:Commands:Sign,
  pack:      Tungsten:Bit:Commands:Pack,
  signup:    Tungsten:Bit:Commands:Signup,
  login:     Tungsten:Bit:Commands:Login,
  create:    Tungsten:Bit:Commands:Create,
  register:  Tungsten:Bit:Commands:Register,
  yank:      Tungsten:Bit:Commands:Yank,
  search:    Tungsten:Bit:Commands:Search,
  clean:     Tungsten:Bit:Commands:Clean,
  generate:  Tungsten:Bit:Commands:Generate,
  destroy:   Tungsten:Bit:Commands:Destroy,
  list:      Tungsten:Bit:Commands:List,
  show:      Tungsten:Bit:Commands:Show,
  update:    Tungsten:Bit:Commands:Update,
  outdated:  Tungsten:Bit:Commands:Outdated,
  upgrade:   Tungsten:Bit:Commands:Upgrade,
  prune:     Tungsten:Bit:Commands:Prune,
  info:      Tungsten:Bit:Commands:Info,
  env:       Tungsten:Bit:Commands:Env,
  doctor:    Tungsten:Bit:Commands:Doctor,
  audit:     Tungsten:Bit:Commands:Audit,
  help:      Tungsten:Bit:Commands:Help
}

# Main entry point — parse argv and dispatch to the appropriate command
-> run(argv)
  name = nil
  args = []
  if argv != nil && argv.size() > 0
    name = argv[0]
    if argv.size() > 1
      args = argv.slice(1, argv.size())

  case name
  when nil, "help"
    Tungsten:Bit:Commands:Help.new(args).execute
  else
    command_class = commands[name.to_sym]
    if command_class
      command_class.new(args).execute
    else
      << "Unknown command: " + name.to_s
      << "Run `bit help` for available commands."
      exit 1

-> version
  Version:STRING

run(argv())
