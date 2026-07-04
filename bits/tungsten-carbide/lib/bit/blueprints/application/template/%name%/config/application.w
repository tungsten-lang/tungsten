# %class_name% — application configuration
use Tungsten:Carbide

+ %class_name%Application < Carbide:Application
  -> configure
    config.app_name    = "%name%"
    config.secret_key  = ENV["SECRET_KEY"] || "change-me-in-production"
    config.time_zone   = "UTC"

    # Session
    config.session_store = :cookie

    # Logging
    config.log_level = :debug

    # Database
    config.database = Database.config_for(environment)
