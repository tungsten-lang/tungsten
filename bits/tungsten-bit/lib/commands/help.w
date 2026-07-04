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
      abort "Unknown command: " + target

    say command_class.new([]).usage

  -> command_for(name)
    case name
      "install"  => Install
      "new"      => New
      "build"    => Build
      "spec"     => Spec
      "publish"  => Publish
      "push"     => Push
      "sign"     => Sign
      "pack"     => Pack
      "signup"   => Signup
      "login"    => Login
      "create"   => Create
      "register" => Register
      "yank"     => Yank
      "search"   => Search
      "clean"    => Clean
      "generate" => Generate
      "destroy"  => Destroy
      "list"     => List
      "show"     => Show
      "update"   => Update
      "outdated" => Outdated
      "upgrade"  => Upgrade
      "prune"    => Prune
      "info"     => Info
      "env"      => Env
      "doctor"   => Doctor
      "audit"    => Audit
      "help"     => Help
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
