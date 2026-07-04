in Tungsten:Carbide:Blueprints

+ FacadeBlueprint < Bit:Blueprint
  -> description
    "Generate a facade (service object)"

  -> usage
    "bit generate facade NAME [options]"

  -> arguments
    [{name: "name", required: true, desc: "Facade name (e.g. publish_version)"}]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    {
      "lib/facades/%file_name%.w":      "lib/facades/#{file_name}.w",
      "spec/facades/%file_name%_spec.w": "spec/facades/#{file_name}_spec.w"
    }
