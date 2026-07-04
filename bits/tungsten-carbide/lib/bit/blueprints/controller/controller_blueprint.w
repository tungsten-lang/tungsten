# Generates an HTTP controller with specified actions
in Tungsten:Carbide:Blueprints

+ ControllerBlueprint < Bit:Blueprint
  -> description
    "Generate an HTTP controller with actions"

  -> usage
    "bit generate controller NAME [action action ...] [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Controller name (e.g. posts, users)"},
      {name: "actions", required: false, variadic: true, desc: "Action names (e.g. index show create)"}
    ]

  -> options
    [
      {name: "--no-spec", default: false, desc: "Skip generating spec file"},
      {name: "--no-views", default: false, desc: "Skip generating view templates"},
      {name: "--api", default: false, desc: "Generate API controller (JSON only)"}
    ]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    mappings = {
      "lib/controllers/%file_name%_controller.w":      "lib/controllers/#{file_name}_controller.w",
      "spec/controllers/%file_name%_controller_spec.w": "spec/controllers/#{file_name}_controller_spec.w"
    }

    unless option?(:no_views) || option?(:api)
      actions.each -> (action)
        mappings["lib/views/%file_name%/#{action}.slim"] = "lib/views/#{file_name}/#{action}.slim"

    mappings
