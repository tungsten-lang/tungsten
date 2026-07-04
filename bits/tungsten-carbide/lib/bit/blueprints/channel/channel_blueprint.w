in Tungsten:Carbide:Blueprints

+ ChannelBlueprint < Bit:Blueprint
  -> description
    "Generate a real-time channel"

  -> usage
    "bit generate channel NAME [options]"

  -> arguments
    [{name: "name", required: true, desc: "Channel name (e.g. notifications)"}]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    file_name = name.underscore
    {
      "lib/channels/%file_name%_channel.w":      "lib/channels/#{file_name}_channel.w",
      "spec/channels/%file_name%_channel_spec.w": "spec/channels/#{file_name}_channel_spec.w"
    }
