# Generates a lookup (query object) for encapsulated queries
in Tungsten:Carbide:Blueprints

+ LookupBlueprint < Bit:Blueprint
  -> description
    "Generate a lookup (query object) for encapsulated database queries"

  -> usage
    "bit generate lookup NAME [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Lookup name (e.g. active_users, recent_posts)"}
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
      "lib/lookups/%file_name%_lookup.w":      "lib/lookups/#{file_name}_lookup.w",
      "spec/lookups/%file_name%_lookup_spec.w": "spec/lookups/#{file_name}_lookup_spec.w"
    }
