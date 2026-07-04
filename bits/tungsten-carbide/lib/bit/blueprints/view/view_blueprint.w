# Generates a view class (the object that assembles data for templates)
in Tungsten:Carbide:Blueprints

+ ViewBlueprint < Bit:Blueprint
  -> description
    "Generate a view class that assembles data for template rendering"

  -> usage
    "bit generate view NAME [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "View name (e.g. posts/index, users/show)"}
    ]

  -> options
    [
      {name: "--no-spec", default: false, desc: "Skip generating spec file"},
      {name: "--no-template", default: false, desc: "Skip generating the companion template file"}
    ]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    mappings = {
      "lib/views/%file_name%_view.w":      "lib/views/#{file_name}_view.w",
      "spec/views/%file_name%_view_spec.w": "spec/views/#{file_name}_view_spec.w"
    }

    unless option?(:no_template)
      mappings["lib/views/%file_name%/index.slim"] = "lib/views/#{file_name}/index.slim"

    mappings
