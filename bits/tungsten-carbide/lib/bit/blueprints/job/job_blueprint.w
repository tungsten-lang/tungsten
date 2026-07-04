in Tungsten:Carbide:Blueprints

+ JobBlueprint < Bit:Blueprint
  -> description
    "Generate a background job"

  -> usage
    "bit generate job NAME [options]"

  -> arguments
    [{name: "name", required: true, desc: "Job name (e.g. send_welcome_email)"}]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    {
      "lib/jobs/%file_name%_job.w":      "lib/jobs/#{file_name}_job.w",
      "spec/jobs/%file_name%_job_spec.w": "spec/jobs/#{file_name}_job_spec.w"
    }
