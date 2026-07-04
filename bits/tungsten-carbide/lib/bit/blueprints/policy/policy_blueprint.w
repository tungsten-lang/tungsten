# Generates an authorization policy
in Tungsten:Carbide:Blueprints

+ PolicyBlueprint < Bit:Blueprint
  -> description
    "Generate an authorization policy"

  -> usage
    "bit generate policy NAME [options]"

  -> arguments
    [{name: "name", required: true, desc: "Policy name (e.g. bit, account)"}]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    {
      "lib/policies/%file_name%_policy.w":      "lib/policies/#{file_name}_policy.w",
      "spec/policies/%file_name%_policy_spec.w": "spec/policies/#{file_name}_policy_spec.w"
    }
