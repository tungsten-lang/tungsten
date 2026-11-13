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

+ Files < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Print the native AV source files for this toolchain"

  -> usage
    "bit av files \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    CLI.new(@raw_args, "files").files

+ Gc < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Preview or remove expired failed jobs and temporary candidates"

  -> usage
    "bit av gc \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "gc")
    context.load
    context.emit(context.collect)

+ Init < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Add declarative AV settings to a project Bitfile"

  -> usage
    "bit av init \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "init")
    context.emit(context.init)

+ Plan < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Resolve output profiles and show a read-only execution plan"

  -> usage
    "bit av plan \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "plan")
    context.load
    context.emit(Planner.new(context.project, context.media).build(context.profiles, false))

+ Publish < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Publish verified outputs to a named destination"

  -> usage
    "bit av publish \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "publish")
    context.load
    context.emit(context.publish)

+ Qc < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Run final-file quality checks"

  -> usage
    "bit av qc \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "qc")
    context.load
    context.emit(context.verify)

+ Quality < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Probe and select a passing bitrate without activating outputs"

  -> usage
    "bit av quality \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "quality")
    context.load
    names = context.profiles
    state = Pipeline.new(context.project, context.media).render(names, true)
    context.emit_job(state)

+ Render < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Render and atomically activate verified outputs"

  -> usage
    "bit av render \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "render")
    context.load
    names = context.profiles
    state = Pipeline.new(context.project, context.media).render(names, false)
    context.emit_job(state)

+ Share < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Render the share profile and its dependencies"

  -> usage
    "bit av share \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "share")
    context.load
    names = context.profiles
    names = ["share"] if names.size == 0
    state = Pipeline.new(context.project, context.media).render(names, false)
    context.emit_job(state)

+ Short < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Render the short profile and its dependencies"

  -> usage
    "bit av short \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "short")
    context.load
    names = context.profiles
    names = ["short"] if names.size == 0
    state = Pipeline.new(context.project, context.media).render(names, false)
    context.emit_job(state)

+ Stage < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Stage verified outputs at a named destination"

  -> usage
    "bit av stage \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "stage")
    context.load
    context.emit(context.publish)

+ Status < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Show the latest project job"

  -> usage
    "bit av status \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "status")
    context.load
    context.emit(context.status)

+ Verify < Tungsten:Bit:Command
  rw :raw_args
  -> summary
    "Verify delivered media and frozen QC inputs"

  -> usage
    "bit av verify \[--project DIR] \[--profile NAME] \[--json]"

  -> execute
    context = CLI.new(@raw_args, "verify")
    context.load
    context.emit(context.verify)

+ Dispatch
  -> .run(name, args)
    if name == "doctor"
      Av:CLI.run(Doctor, args)
    elsif name == "files"
      Av:CLI.run(Files, args)
    elsif name == "gc"
      Av:CLI.run(Gc, args)
    elsif name == "init"
      Av:CLI.run(Init, args)
    elsif name == "plan"
      Av:CLI.run(Plan, args)
    elsif name == "publish"
      Av:CLI.run(Publish, args)
    elsif name == "qc"
      Av:CLI.run(Qc, args)
    elsif name == "quality"
      Av:CLI.run(Quality, args)
    elsif name == "render"
      Av:CLI.run(Render, args)
    elsif name == "share"
      Av:CLI.run(Share, args)
    elsif name == "short"
      Av:CLI.run(Short, args)
    elsif name == "stage"
      Av:CLI.run(Stage, args)
    elsif name == "status"
      Av:CLI.run(Status, args)
    elsif name == "verify"
      Av:CLI.run(Verify, args)
    else
      << JSON.encode({"ok": false, "error": "unknown AV command: " + name})
      exit(2)
