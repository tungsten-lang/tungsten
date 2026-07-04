use Tungsten:Spec
use Tungsten:Spec:Carbide

# Load the application
ENV["CARBIDE_ENV"] = "test"
use ../lib/%file_name%

Spec.configure ->
  # Run each spec in a transaction that rolls back
  config.around_each -> (example)
    Carbide:Database.transaction(rollback: :always) ->
      example.run
