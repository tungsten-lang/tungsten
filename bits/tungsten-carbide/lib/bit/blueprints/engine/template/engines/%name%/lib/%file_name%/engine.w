# %class_name%::Engine — mountable engine configuration
use Tungsten:Carbide

in %class_name%

+ Engine < Carbide:Engine
  # Isolate this engine's namespace
  isolate_namespace %class_name%

  -> initializers
    [
      {
        name: "%name%.assets",
        block: -> (app)
          app.config.assets.paths.push(root.join("lib", "assets"))
      },
      {
        name: "%name%.routes",
        block: -> (app)
          app.routes.draw ->
            mount %class_name%:Engine, at: "/%name%"
      }
    ]
