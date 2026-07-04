# Generates a timestamped database migration
in Tungsten:Carbide:Blueprints

+ MigrationBlueprint < Bit:Blueprint
  -> description
    "Generate a database migration"

  -> usage
    "bit generate migration NAME [column:type column:type ...] [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Migration name (e.g. create_users, add_email_to_posts)"},
      {name: "columns", required: false, variadic: true, desc: "Column definitions (e.g. name:string email:string age:integer)"}
    ]

  -> options
    [
      {name: "--table", desc: "Target table name (inferred from migration name if not specified)"}
    ]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    timestamp = Time.now.strftime("%Y%m%d%H%M%S")
    {
      "db/migrate/%timestamp%_%file_name%.w": "db/migrate/#{timestamp}_#{file_name}.w"
    }
