in Tungsten:Bit:Commands

+ Help < Command
  -> summary
    "Show help for bit commands"

  -> usage
    "USAGE\n  bit help COMMAND (options)\n\nOPTIONS\n"

  -> execute
    target = .args.first
    if target == nil
      say usage
      return

    if target == "commands"
      command_names.each -> (name)
        command_class = command_for(name)
        say "  " + name + " - " + command_class.new([]).summary
      return

    command_class = command_for(target)
    if command_class == nil
      return true if PackageCommands.help(target)
      abort "Unknown command: " + target

    say command_class.new([]).usage

  -> command_for(name)
    case name
      "install"  => Tungsten:Bit:Commands:Install
      "new"      => Tungsten:Bit:Commands:New
      "build"    => Tungsten:Bit:Commands:Build
      "spec"     => Tungsten:Bit:Commands:Spec
      "publish"  => Tungsten:Bit:Commands:Publish
      "push"     => Tungsten:Bit:Commands:Push
      "sign"     => Tungsten:Bit:Commands:Sign
      "pack"     => Tungsten:Bit:Commands:Pack
      "signup"   => Tungsten:Bit:Commands:Signup
      "login"    => Tungsten:Bit:Commands:Login
      "create"   => Tungsten:Bit:Commands:Create
      "register" => Tungsten:Bit:Commands:Register
      "yank"     => Tungsten:Bit:Commands:Yank
      "search"   => Tungsten:Bit:Commands:Search
      "clean"    => Tungsten:Bit:Commands:Clean
      "generate" => Tungsten:Bit:Commands:Generate
      "destroy"  => Tungsten:Bit:Commands:Destroy
      "list"     => Tungsten:Bit:Commands:List
      "show"     => Tungsten:Bit:Commands:Show
      "update"   => Tungsten:Bit:Commands:Update
      "outdated" => Tungsten:Bit:Commands:Outdated
      "upgrade"  => Tungsten:Bit:Commands:Upgrade
      "prune"    => Tungsten:Bit:Commands:Prune
      "info"     => Tungsten:Bit:Commands:Info
      "env"      => Tungsten:Bit:Commands:Env
      "doctor"   => Tungsten:Bit:Commands:Doctor
      "audit"    => Tungsten:Bit:Commands:Audit
      "help"     => Tungsten:Bit:Commands:Help
      => nil

  -> command_names
    [
      "install",
      "new",
      "build",
      "spec",
      "publish",
      "push",
      "sign",
      "pack",
      "signup",
      "login",
      "create",
      "register",
      "yank",
      "search",
      "clean",
      "generate",
      "destroy",
      "list",
      "show",
      "update",
      "outdated",
      "upgrade",
      "prune",
      "info",
      "env",
      "doctor",
      "audit",
      "help"
    ]
