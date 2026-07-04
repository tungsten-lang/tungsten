# Generates a route entry in config/routes.w
in Tungsten:Carbide:Blueprints

+ RouteBlueprint < Bit:Blueprint
  -> description
    "Generate a route entry for config/routes.w"

  -> usage
    "bit generate route NAME [options]"

  -> arguments
    [
      {name: "name", required: true, desc: "Resource or path name"}
    ]

  -> options
    [
      {name: "--type", default: "resources", desc: "Route type: resources, get, post, put, patch, delete"},
      {name: "--to", desc: "Controller#action target (for single routes)"},
      {name: "--path", desc: "Custom URL path"}
    ]

  -> template_dir
    File.join(__dir__, "template")

  -> file_mappings(name)
    # Route blueprint injects into an existing file rather than creating new ones
    {}

  -> after_generate(name)
    route_file = "config/routes.w"
    route_line = build_route_line(name)
    inject_into_file(route_file, route_line, after: "Carbide.routes.draw ->")

  -> build_route_line(name)
    type = option(:type, "resources")
    case type
      "resources" => "  resources :#{name}"
      "get"       => "  get \"/#{name}\", to: \"#{option(:to)}\""
      "post"      => "  post \"/#{name}\", to: \"#{option(:to)}\""
      "put"       => "  put \"/#{name}\", to: \"#{option(:to)}\""
      "patch"     => "  patch \"/#{name}\", to: \"#{option(:to)}\""
      "delete"    => "  delete \"/#{name}\", to: \"#{option(:to)}\""
