# Generates a full scaffold: model + controller + views + serializer + migration + routes
in Tungsten:Carbide:Blueprints

+ ScaffoldBlueprint < Bit:Blueprint
  -> description
    "Generate a full scaffold with model, controller, views, serializer, and migration"

  -> usage
    "bit generate scaffold NAME [attribute:type ...] [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Resource name (e.g. post, article)"},
      {name: "attributes", required: false, variadic: true, desc: "Attribute definitions (e.g. title:string body:text published:boolean)"}
    ]

  -> options
    [
      {name: "--no-migration", default: false, desc: "Skip migration"},
      {name: "--no-spec", default: false, desc: "Skip spec files"},
      {name: "--api", default: false, desc: "Generate API-only scaffold (serializer instead of views)"}
    ]

  -> template_dir
    File.join(__dir__, "template")

  -> invoke_blueprints
    blueprints = [
      {blueprint: "model",      args: [name] + extra_args, options: inherited_options},
      {blueprint: "controller",  args: [name, "index", "show", "new", "create", "edit", "update", "destroy"], options: inherited_options},
      {blueprint: "route",       args: [name], options: {type: "resources"}}
    ]

    if option?(:api)
      blueprints.push({blueprint: "serializer", args: [name] + extra_args, options: inherited_options})
    else
      blueprints.push({blueprint: "view", args: [name], options: inherited_options})

    blueprints

  -> file_mappings(name)
    # Delegated to composed blueprints via invoke_blueprints
    {}
