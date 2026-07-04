# bit login — store a registry token or log in with registry credentials
in Tungsten:Bit:Commands

+ Login < Command
  -> summary
    "Log in to a bit registry"

  -> usage
    "USAGE\n  bit login HANDLE_OR_EMAIL (options)\n\nOPTIONS\n      --registry URL       Registry URL\n      --password PASSWORD  Registry password\n      --token TOKEN        Store an existing API token\n"

  -> execute
    registry = option(:registry, DEFAULT_REGISTRY)
    token = option(:token)
    if token != nil
      Auth.save_token(token, registry)
      say "Saved token for " + registry
      return

    auth = Auth.load
    handle = .args.first || option(:handle) || option(:email) || auth.handle || auth.email
    handle = prompt_line("Handle or email", handle, false)
    password = option(:password) || prompt_line("Password", nil, false)
    abort "Handle/email is required" unless handle
    abort "Password is required" unless password

    response = Registry:Client.new(registry).login(handle, password)
    if response.status == :ok
      Auth.save_token(response.message, registry)
      say "Logged in to " + registry
    else
      abort response.message
