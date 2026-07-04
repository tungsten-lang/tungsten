in Tungsten:Carbide:Blueprints

+ EventBlueprint < Bit:Blueprint
  -> description
    "Generate a domain event"

  -> usage
    "bit generate event NAME [options]"

  -> arguments
    [{name: "name", required: true, desc: "Event name (e.g. version_published)"}]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    {
      "lib/events/%file_name%.w":      "lib/events/#{file_name}.w",
      "spec/events/%file_name%_spec.w": "spec/events/#{file_name}_spec.w"
    }
