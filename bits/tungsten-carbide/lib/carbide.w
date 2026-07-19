# Tungsten Carbide — a web application framework for Tungsten
# Named for the hardest compound of tungsten — strong, sharp, built to cut.
#
# Carbide provides the full stack: routing, controllers, models, views,
# migrations, background jobs, mailers, and serializers.

in Tungsten:Carbide

# application pulls the working core: forge (cross-bit), route, controller.
use application
use model
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

# --- CLI (bin/carbide) ---

-> print_usage
  << "Tungsten Carbide [VERSION] — full-stack web framework for Tungsten"
  << ""
  << "Usage: carbide COMMAND"
  << ""
  << "Commands:"
  << "  version    Print the Carbide version"
  << "  selftest   Run the framework's built-in smoke checks"
  << "  help       Show this help"

# Pure-logic smoke checks over the routing core. Returns a list of
# failure messages (empty = healthy).
-> selftest_failures
  failures = []

  r = Route.new(:GET, "/users/:id", "UsersController", :show)
  failures.push("param route should match /users/42") unless r.match_path?("/users/42")
  failures.push("param route should not match /users") if r.match_path?("/users")
  failures.push("literal segment should not match /posts/42") if r.match_path?("/posts/42")
  failures.push("extract_params should capture :id") unless r.extract_params("/users/42")[:id] == "42"

  glob = Route.new(:GET, "/files/*path", "FilesController", :show)
  failures.push("glob route should match /files/a") unless glob.match_path?("/files/a")

  failures

-> run_cli(args)
  cmd = "help"
  cmd = args[0] if args.size > 0

  if cmd == "version" || cmd == "--version" || cmd == "-v"
    << "Tungsten Carbide [VERSION]"
  elsif cmd == "selftest"
    failures = selftest_failures
    if failures.empty?
      << "PASS — routing core healthy"
    else
      failures.each -> (f)
        << "FAIL: [f]"
      exit(1)
  elsif cmd == "help" || cmd == "--help" || cmd == "-h"
    print_usage
  else
    << "carbide: unknown command '[cmd]'"
    << ""
    print_usage
    exit(1)

run_cli(argv())
