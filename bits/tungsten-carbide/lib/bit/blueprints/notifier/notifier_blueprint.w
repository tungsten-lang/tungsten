in Tungsten:Carbide:Blueprints

+ NotifierBlueprint < Bit:Blueprint
  -> description
    "Generate a multi-channel notifier"

  -> usage
    "bit generate notifier NAME [options]"

  -> arguments
    [{name: "name", required: true, desc: "Notifier name (e.g. account)"}]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    {
      "lib/notifiers/%file_name%_notifier.w":      "lib/notifiers/#{file_name}_notifier.w",
      "spec/notifiers/%file_name%_notifier_spec.w": "spec/notifiers/#{file_name}_notifier_spec.w"
    }
