# Generates a full REST resource: model + controller + migration + route
in Tungsten:Carbide:Blueprints

+ ResourceBlueprint < Bit:Blueprint
  -> description
    "Generate a full REST resource (model, controller, migration, routes)"

  -> usage
    "bit generate resource NAME [attribute:type ...] [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Resource name (e.g. post, comment)"},
      {name: "attributes", required: false, variadic: true, desc: "Attribute definitions (e.g. title:string body:text)"}
    ]

  -> options
    [
      {name: "--no-migration", default: false, desc: "Skip migration"},
      {name: "--no-spec", default: false, desc: "Skip spec files"},
      {name: "--api", default: false, desc: "Generate API-only resource (no views)"}
    ]

  -> template_dir
    File.join(__dir__, "template")

  -> invoke_blueprints
    # Resource composes model + controller + route blueprints
    [
      {blueprint: "model",      args: [name] + extra_args, options: inherited_options},
      {blueprint: "controller",  args: [name, "index", "show", "new", "create", "edit", "update", "destroy"], options: inherited_options},
      {blueprint: "route",       args: [name], options: {type: "resources"}}
    ]

  -> file_mappings(name)
    # Delegated to composed blueprints via invoke_blueprints
    {}
