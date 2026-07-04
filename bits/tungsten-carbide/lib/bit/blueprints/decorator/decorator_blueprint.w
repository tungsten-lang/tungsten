# Generates a decorator/presenter wrapping a model
in Tungsten:Carbide:Blueprints

+ DecoratorBlueprint < Bit:Blueprint
  -> description
    "Generate a decorator (presenter) that wraps a model"

  -> usage
    "bit generate decorator NAME [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Name of the model to decorate (e.g. user, post)"}
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
      "lib/decorators/%file_name%_decorator.w":      "lib/decorators/#{file_name}_decorator.w",
      "spec/decorators/%file_name%_decorator_spec.w": "spec/decorators/#{file_name}_decorator_spec.w"
    }
