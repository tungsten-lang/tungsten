in Tungsten:Carbide:Blueprints

+ ConfigBlueprint < Bit:Blueprint
  -> description
    "Generate a typed configuration"

  -> usage
    "bit generate config NAME [options]"

  -> arguments
    [{name: "name", required: true, desc: "Config name (e.g. database, redis)"}]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    {
      "lib/config/%file_name%_config.w":      "lib/config/#{file_name}_config.w",
      "spec/config/%file_name%_config_spec.w": "spec/config/#{file_name}_config_spec.w"
    }
