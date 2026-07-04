# Generates a JSON serializer for a model
in Tungsten:Carbide:Blueprints

+ SerializerBlueprint < Bit:Blueprint
  -> description
    "Generate a JSON serializer for API responses"

  -> usage
    "bit generate serializer NAME [attribute attribute ...] [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Model name to serialize (e.g. user, post)"},
      {name: "attributes", required: false, variadic: true, desc: "Attributes to include in JSON output"}
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
      "lib/serializers/%file_name%_serializer.w":      "lib/serializers/#{file_name}_serializer.w",
      "spec/serializers/%file_name%_serializer_spec.w": "spec/serializers/#{file_name}_serializer_spec.w"
    }
