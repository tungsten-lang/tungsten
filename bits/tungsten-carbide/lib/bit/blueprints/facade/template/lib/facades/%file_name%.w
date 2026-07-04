in Facades

+ %class_name%[Facade]
  -> call
    # Step 1
    step :validate ->
      # validate inputs
      self.params

    # Step 2
    step :execute ->
      # perform the operation
      nil

    self.succeed(self.context)
