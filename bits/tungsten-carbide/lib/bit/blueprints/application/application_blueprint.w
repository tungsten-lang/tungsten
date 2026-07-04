# Generates a full Tungsten Carbide application scaffold
in Tungsten:Carbide:Blueprints

+ ApplicationBlueprint < Bit:Blueprint
  -> description
    "Generate a new Tungsten Carbide application"

  -> usage
    "bit generate application NAME [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Application name"}
    ]

  -> options
    [
      {name: "--database", default: "postgres", desc: "Database adapter (postgres, sqlite, mysql)"},
      {name: "--skip-git", default: false, desc: "Skip git initialization"},
      {name: "--skip-spec", default: false, desc: "Skip spec directory"},
      {name: "--api-only", default: false, desc: "Generate API-only application (no views/assets)"}
    ]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    mappings = {
      "%name%/Bitfile":                               "#{name}/Bitfile",
      "%name%/README.md":                             "#{name}/README.md",
      "%name%/.gitignore":                            "#{name}/.gitignore",
      "%name%/config/application.w":                  "#{name}/config/application.w",
      "%name%/config/routes.w":                       "#{name}/config/routes.w",
      "%name%/config/database.w":                     "#{name}/config/database.w",
      "%name%/config/environments/development.w":     "#{name}/config/environments/development.w",
      "%name%/config/environments/production.w":      "#{name}/config/environments/production.w",
      "%name%/config/environments/test.w":            "#{name}/config/environments/test.w",
      "%name%/config/initializers/session.w":         "#{name}/config/initializers/session.w",
      "%name%/lib/%file_name%.w":                     "#{name}/lib/#{file_name}.w",
      "%name%/lib/%file_name%/version.w":             "#{name}/lib/#{file_name}/version.w",
      "%name%/lib/controllers/application_controller.w": "#{name}/lib/controllers/application_controller.w",
      "%name%/lib/models/.gitkeep":                   "#{name}/lib/models/.gitkeep",
      "%name%/lib/views/layouts/application.slim":     "#{name}/lib/views/layouts/application.slim",
      "%name%/db/migrate/.gitkeep":                   "#{name}/db/migrate/.gitkeep",
      "%name%/db/seeds.w":                            "#{name}/db/seeds.w",
      "%name%/spec/spec_helper.w":                    "#{name}/spec/spec_helper.w",
      "%name%/bin/server":                            "#{name}/bin/server",
      "%name%/bin/console":                           "#{name}/bin/console",
      "%name%/bin/setup":                             "#{name}/bin/setup",
      "%name%/public/favicon.ico":                    "#{name}/public/favicon.ico",
      "%name%/public/robots.txt":                     "#{name}/public/robots.txt",
      "%name%/log/.gitkeep":                          "#{name}/log/.gitkeep",
      "%name%/tmp/.gitkeep":                          "#{name}/tmp/.gitkeep"
    }

    unless option?(:api_only)
      mappings.merge!({
        "%name%/lib/assets/stylesheets/application.css": "#{name}/lib/assets/stylesheets/application.css",
        "%name%/lib/assets/scripts/application.w":       "#{name}/lib/assets/scripts/application.w"
      })

    mappings
