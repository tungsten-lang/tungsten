# Session configuration
Carbide.app.configure ->
  config.session_store  = :cookie
  config.session_key    = "_%name%_session"
  config.session_secret = ENV["SESSION_SECRET"] || config.secret_key
