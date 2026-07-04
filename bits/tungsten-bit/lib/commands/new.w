# bit new — scaffold a new Tungsten project or bit
in Tungsten:Bit:Commands

+ New < Command
  -> summary
    "Create a new Tungsten project"

  -> usage
    "USAGE\n  bit new NAME (options)\n\nOPTIONS\n  -t, --type TYPE   Project type: app, bit, lib\n      --skip-spec   Don't generate spec directory\n      --skip-git    Don't initialize git repository\n"

  -> execute
    name = .args.first
    abort "Please provide a project name: bit new NAME" unless name

    type = option(:type, "app")
    target = File.join(Dir.pwd, name)

    if File.exists?(target)
      abort "Directory " + name + " already exists"

    say "Creating new Tungsten " + type + ": " + name

    # Create directory structure based on project type
    dirs = base_dirs(name)
    unless flag?(:skip_spec)
      spec_dirs(name).each -> (dir)
        dirs.push(dir)
    type_dirs(name, type).each -> (dir)
      dirs.push(dir)

    dirs.each -> (dir)
      FileUtils.mkdir_p(dir)
      verbose("  create " + dir)

    # Generate template files
    templates = base_templates(name, type)
    templates.each -> (path, content)
      File.write(path, content)
      verbose("  create " + path)

    # Initialize git
    unless flag?(:skip_git)
      System.exec("git -C " + shell_quote(target) + " init")
      System.exec("git -C " + shell_quote(target) + " add .")
      System.exec("git -C " + shell_quote(target) + " commit -m 'Initial commit'")
      verbose("  init   git repository")

    say ""
    say "Done! cd " + name + " to get started."

  -> base_dirs(name)
    [
      name,
      name + "/lib",
      name + "/lib/" + name,
      name + "/bin"
    ]

  -> spec_dirs(name)
    [
      name + "/spec",
      name + "/spec/" + name
    ]

  -> type_dirs(name, type)
    case type
      "app" => [name + "/config", name + "/db"]
      "bit" => []
      "lib" => []
      =>      []

  -> base_templates(name, type)
    {
      name + "/Bitfile" => bitfile_template(name, type),
      name + "/README.md" => readme_template(name),
      name + "/lib/" + name + ".w" => lib_template(name),
      name + "/lib/" + name + "/version.w" => version_template(name),
      name + "/.gitignore" => gitignore_template
    }

  -> bitfile_template(name, type)
    text = "tungsten \"" + name + "-0.1.0\"\n\n"
    text = text + "name \"" + name + "\"\n"
    text = text + "version \"0.1.0\"\n\n"
    text = text + "# Add your dependencies here\n"
    text = text + "# bit \"tungsten-spec\", group: :spec\n"
    text

  -> readme_template(name)
    text = "# " + project_class_name(name) + "\n\n"
    text = text + "A Tungsten " + name + " project.\n\n"
    text = text + "# Getting Started\n\n"
    text = text + "    bit install\n"
    text = text + "    bit build\n"
    text

  -> lib_template(name)
    text = "# " + name + " - main entry point\n"
    text = text + "in " + project_class_name(name) + "\n"
    text

  -> version_template(name)
    text = "in " + project_class_name(name) + ":Version\n"
    text = text + "STRING = \"0.1.0\"\n"
    text

  -> gitignore_template
    "/vendor\n/tmp\n*.log\nBitfile.lock\n"
