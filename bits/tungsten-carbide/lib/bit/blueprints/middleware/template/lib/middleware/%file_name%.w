in Middleware

+ %class_name%[Middleware]
  -> call(request, next_handler)
    # Before request
    response = next_handler.call(request)
    # After request
    response
