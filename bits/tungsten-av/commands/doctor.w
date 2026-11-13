use ../lib/cli

in Av:Commands

+ Doctor < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Check native AV capabilities, inputs and resource budgets"

  -> usage
    "bit av doctor \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "doctor")
    context.load
    plan = Planner.new(context.project, context.media).build(context.profiles, false)
    versions = {"tungsten": context.project.toolchain, "media_runtime": plan["capabilities"]["implementation"]}
    context.emit({"ok": plan["ready"], "project": context.project.name, "toolchain": context.project.toolchain, "capabilities": plan["capabilities"], "tool_versions": versions, "inputs": plan["inputs"].size, "profiles": plan["profiles"].keys, "disk": plan["disk"], "implementation": "native Tungsten"})
    exit(1) if !plan["ready"]

Av:CLI.run(Av:Commands:Doctor, argv())
