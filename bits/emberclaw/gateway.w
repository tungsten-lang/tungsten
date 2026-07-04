+ Gateway
  rw :status

  -> new
    @status = "stopped"

  -> start
    @status = "running"
    "Gateway started"

  -> stop
    @status = "stopped"
    "Gateway stopped"

  -> status
    @status
