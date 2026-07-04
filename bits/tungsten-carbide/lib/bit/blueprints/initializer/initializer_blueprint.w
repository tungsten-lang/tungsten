# Generates an application initializer
in Tungsten:Carbide:Blueprints

+ InitializerBlueprint < Bit:Blueprint
  -> description
    "Generate an application initializer (startup configuration hook)"

  -> usage
    "bit generate initializer NAME [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Initializer name (e.g. session, cors, logging)"}
    ]

  -> options
    []

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    {
      "config/initializers/%file_name%.w": "config/initializers/#{file_name}.w"
    }
