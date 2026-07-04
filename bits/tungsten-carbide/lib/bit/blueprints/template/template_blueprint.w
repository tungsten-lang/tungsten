# Generates a view template file
in Tungsten:Carbide:Blueprints

+ TemplateBlueprint < Bit:Blueprint
  -> description
    "Generate a view template file"

  -> usage
    "bit generate template NAME [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Template path (e.g. posts/show, users/profile)"}
    ]

  -> options
    [
      {name: "--layout", default: false, desc: "Generate as a layout template"},
      {name: "--partial", default: false, desc: "Generate as a partial (prefixed with _)"}
    ]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore

    if option?(:layout)
      {"lib/views/layouts/%file_name%.slim": "lib/views/layouts/#{file_name}.slim"}
    elsif option?(:partial)
      parts = file_name.split("/")
      parts[-1] = "_#{parts[-1]}"
      partial_path = parts.join("/")
      {"lib/views/%file_name%.slim": "lib/views/#{partial_path}.slim"}
    else
      {"lib/views/%file_name%.slim": "lib/views/#{file_name}.slim"}
