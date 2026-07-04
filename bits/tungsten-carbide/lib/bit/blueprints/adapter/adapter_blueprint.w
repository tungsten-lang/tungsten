# Generates a database adapter for connecting to a data source
in Tungsten:Carbide:Blueprints

+ AdapterBlueprint < Bit:Blueprint
  -> description
    "Generate a database adapter for connecting to a data source"

  -> usage
    "bit generate adapter NAME [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Name of the adapter (e.g. postgres, redis)"}
    ]

  -> options
    [
      {name: "--pool-size", default: 5, desc: "Default connection pool size"},
      {name: "--timeout", default: 5000, desc: "Default connection timeout in ms"}
    ]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    {
      "lib/%file_name%_adapter.w":      "lib/#{file_name}_adapter.w",
      "spec/%file_name%_adapter_spec.w": "spec/#{file_name}_adapter_spec.w"
    }
