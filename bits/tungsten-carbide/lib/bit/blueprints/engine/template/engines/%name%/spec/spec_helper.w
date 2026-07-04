use Tungsten:Spec
use Tungsten:Spec:Carbide

ENV["CARBIDE_ENV"] = "test"
use ../lib/%file_name%

Spec.configure ->
  config.around_each -> (example)
    Carbide:Database.transaction(rollback: :always) ->
      example.run
