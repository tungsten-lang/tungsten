# Generates a data model with attributes, migration, and spec
in Tungsten:Carbide:Blueprints

+ ModelBlueprint < Bit:Blueprint
  -> description
    "Generate a data model with attributes, migration, and spec"

  -> usage
    "bit generate model NAME [attribute:type attribute:type ...] [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Model name (e.g. user, post, comment)"},
      {name: "attributes", required: false, variadic: true, desc: "Attribute definitions (e.g. name:string email:string age:integer)"}
    ]

  -> options
    [
      {name: "--no-migration", default: false, desc: "Skip generating migration"},
      {name: "--no-spec", default: false, desc: "Skip generating spec"},
      {name: "--timestamps", default: true, desc: "Include created_at/updated_at columns"}
    ]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    timestamp = Time.now.strftime("%Y%m%d%H%M%S")
    mappings = {
      "lib/models/%file_name%.w":      "lib/models/#{file_name}.w",
      "spec/models/%file_name%_spec.w": "spec/models/#{file_name}_spec.w"
    }

    unless option?(:no_migration)
      mappings["db/migrate/%timestamp%_create_%file_name%s.w"] =
        "db/migrate/#{timestamp}_create_#{file_name}s.w"

    mappings
