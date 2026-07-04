# %class_name%Transform — data transformation step
# Transforms are composable pipeline stages that take input data
# and produce output data. Chain them with |> for multi-step pipelines.
#
# Usage:
#   result = %class_name%Transform.call(data)
#   result = data |> %class_name%Transform |> AnotherTransform
use Tungsten:Carbide

+ %class_name%Transform
  ro :input
  ro :options

  -> new(@input, **options)
    @options = options

  # Execute the transformation
  -> call
    validate!(@input)
    transform(@input)

  # Override this method with your transformation logic
  -> transform(data)
    # Example:
    #   data.map -> (record)
    #     record.merge(processed_at: Time.now)
    data

  # Validate input before processing
  -> validate!(data)
    <! ArgumentError.new("Input cannot be nil") if data.nil?

  # Class-level shortcut: %class_name%Transform.call(data)
  -> .call(input, **options)
    self.new(input, **options).call

  # Composable: returns a lambda for use in pipelines
  [pure]
  -> .to_proc
    -> (input) self.call(input)
