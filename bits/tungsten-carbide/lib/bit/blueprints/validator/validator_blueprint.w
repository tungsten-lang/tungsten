in Tungsten:Carbide:Blueprints

+ ValidatorBlueprint < Bit:Blueprint
  -> description
    "Generate a reusable validator"

  -> usage
    "bit generate validator NAME [options]"

  -> arguments
    [{name: "name", required: true, desc: "Validator name (e.g. email, bit_name)"}]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    {
      "lib/validators/%file_name%_validator.w":      "lib/validators/#{file_name}_validator.w",
      "spec/validators/%file_name%_validator_spec.w": "spec/validators/#{file_name}_validator_spec.w"
    }
