# bit signup — create a bits.tungsten-lang.org profile
in Tungsten:Bit:Commands

+ Signup < Command
  -> summary
    "Create a registry profile and store local credentials"

  -> usage
    "USAGE\n  bit signup HANDLE (options)\n\nOPTIONS\n      --email EMAIL        Email address for the profile\n      --github-email EMAIL GitHub email address to publish\n      --public-key PATH    SSH public key to associate\n      --registry URL       Registry URL\n      --password PASSWORD  Password for the registry account\n      --token TOKEN        Store an existing API token instead of creating remotely\n      --yes                Accept detected email/key defaults\n      --local              Only write the local profile\n"

  -> execute
    registry = option(:registry, DEFAULT_REGISTRY)
    handle = option(:handle) || .args.first || detected_git_handle()
    email = option(:email) || detected_git_email()
    github_email = option(:github_email) || email
    public_key_path = option(:public_key) || default_public_key_path()

    handle = prompt_line("Handle", handle, flag?(:yes))
    email = prompt_line("Email", email, flag?(:yes))
    github_email = prompt_line("GitHub email", github_email, flag?(:yes))
    public_key_path = prompt_line("Public key", public_key_path, flag?(:yes))

    abort "Handle is required" unless handle
    abort "Email is required" unless email
    abort "Public key path is required" unless public_key_path
    abort "Public key not found: " + public_key_path unless File.exists?(public_key_path)

    public_key = File.read(public_key_path).strip()
    say "Profile"
    say "  handle     " + handle
    say "  email      " + email
    say "  github     " + github_email
    say "  public key " + public_key_path
    unless confirm_line("Create this profile?", flag?(:yes))
      abort "Canceled"

    Auth.save_profile(handle, email, public_key_path, public_key, registry)

    token = option(:token)
    if token != nil
      Auth.save_token(token, registry)
      say "Saved token for " + registry
      return

    if flag?(:local)
      say "Saved local profile in " + bit_profile_path()
      return

    password = option(:password) || prompt_line("Password", nil, false)
    abort "Password is required for remote signup" unless password

    response = Registry:Client.new(registry).signup(handle, email, password, public_key, github_email)
    if response.status == :ok
      Auth.save_token(response.message, registry)
      say "Created profile and saved registry token"
    else
      abort response.message
