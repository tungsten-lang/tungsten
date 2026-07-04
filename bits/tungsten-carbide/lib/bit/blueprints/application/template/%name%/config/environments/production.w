# Production environment configuration
Carbide.app.configure ->
  config.cache_classes  = true
  config.eager_load     = true
  config.log_level      = :info
  config.static_files   = false
  config.force_ssl      = true
  config.show_exceptions = false
