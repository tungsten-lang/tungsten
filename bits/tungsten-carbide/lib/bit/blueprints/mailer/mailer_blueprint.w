# Generates a mailer with specified email methods
in Tungsten:Carbide:Blueprints

+ MailerBlueprint < Bit:Blueprint
  -> description
    "Generate a mailer for sending emails"

  -> usage
    "bit generate mailer NAME [method method ...] [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Mailer name (e.g. user, notification)"},
      {name: "methods", required: false, variadic: true, desc: "Email method names (e.g. welcome reset_password)"}
    ]

  -> options
    [
      {name: "--no-spec", default: false, desc: "Skip generating spec file"}
    ]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    mappings = {
      "lib/mailers/%file_name%_mailer.w":      "lib/mailers/#{file_name}_mailer.w",
      "spec/mailers/%file_name%_mailer_spec.w": "spec/mailers/#{file_name}_mailer_spec.w"
    }

    # Generate a template for each email method
    methods = extra_args || ["notification"]
    methods.each -> (method_name)
      mappings["lib/views/%file_name%_mailer/#{method_name}.slim"] =
        "lib/views/#{file_name}_mailer/#{method_name}.slim"

    mappings
