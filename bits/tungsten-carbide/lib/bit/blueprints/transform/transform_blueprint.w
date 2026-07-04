# Generates a data transform/pipeline step
in Tungsten:Carbide:Blueprints

+ TransformBlueprint < Bit:Blueprint
  -> description
    "Generate a data transform (pipeline processing step)"

  -> usage
    "bit generate transform NAME [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Transform name (e.g. normalize_email, parse_csv)"}
    ]

  -> options
    [
      {name: "--no-spec", default: false, desc: "Skip generating spec file"}
    ]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    {
      "lib/transforms/%file_name%_transform.w":      "lib/transforms/#{file_name}_transform.w",
      "spec/transforms/%file_name%_transform_spec.w": "spec/transforms/#{file_name}_transform_spec.w"
    }
