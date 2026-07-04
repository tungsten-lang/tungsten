in Tungsten:Carbide:Blueprints

+ MiddlewareBlueprint < Bit:Blueprint
  -> description
    "Generate a middleware"

  -> usage
    "bit generate middleware NAME [options]"

  -> arguments
    [{name: "name", required: true, desc: "Middleware name (e.g. rate_limit)"}]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    {
      "lib/middleware/%file_name%.w":      "lib/middleware/#{file_name}.w",
      "spec/middleware/%file_name%_spec.w": "spec/middleware/#{file_name}_spec.w"
    }
