# Generates a mountable engine (plugin) with its own MVC structure
in Tungsten:Carbide:Blueprints

+ EngineBlueprint < Bit:Blueprint
  -> description
    "Generate a mountable engine (self-contained plugin)"

  -> usage
    "bit generate engine NAME [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Engine name (e.g. authentication, blog)"}
    ]

  -> options
    [
      {name: "--mountable", default: true, desc: "Generate as mountable engine"},
      {name: "--full", default: false, desc: "Generate full engine with all directories"}
    ]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    {
      "engines/%name%/Bitfile":                               "engines/#{name}/Bitfile",
      "engines/%name%/lib/%file_name%.w":                     "engines/#{name}/lib/#{file_name}.w",
      "engines/%name%/lib/%file_name%/engine.w":              "engines/#{name}/lib/#{file_name}/engine.w",
      "engines/%name%/lib/%file_name%/version.w":             "engines/#{name}/lib/#{file_name}/version.w",
      "engines/%name%/config/routes.w":                       "engines/#{name}/config/routes.w",
      "engines/%name%/lib/controllers/%file_name%/application_controller.w": "engines/#{name}/lib/controllers/#{file_name}/application_controller.w",
      "engines/%name%/lib/models/.gitkeep":                   "engines/#{name}/lib/models/.gitkeep",
      "engines/%name%/lib/views/layouts/%file_name%/application.slim": "engines/#{name}/lib/views/layouts/#{file_name}/application.slim",
      "engines/%name%/spec/spec_helper.w":                    "engines/#{name}/spec/spec_helper.w"
    }
