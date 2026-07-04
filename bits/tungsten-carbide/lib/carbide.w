# Tungsten Carbide — a web application framework for Tungsten
# Named for the hardest compound of tungsten — strong, sharp, built to cut.
#
# Carbide provides the full stack: routing, controllers, models, views,
# migrations, background jobs, mailers, and serializers.

in Tungsten:Carbide

use application
use controller
use model
use route
use view
use migration
use serializer
use worker
use mailer
use request

constant_alias "WC"

VERSION = "0.1.0"

# Boot the application — called from config/application.w
-> boot(config = {})
  app = Application.new(config)
  app.initialize!
  app

# Shorthand for accessing the running application instance
-> app
  Application.instance
