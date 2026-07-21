# Tungsten Carbide — a web application framework for Tungsten
# Named for the hardest compound of tungsten — strong, sharp, built to cut.
#
# Carbide's working core: routing (route.w), controllers (controller.w)
# with strong-parameter allow-listing (strong_params.w), models with
# validations + an in-memory store (model.w), JSON serialization
# (serializer.w), mustache-style view templates (template.w), and live
# serving through forge (application.w).
# Everything loaded here runs on BOTH engines and is spec-covered
# (spec/*.w).

in Tungsten:Carbide

# template first (no deps); application pulls the rest of the working
# core: forge (cross-bit), route, controller.
use template
use application
use model
use serializer
use strong_params

# The remaining modules under lib/ (migration, worker, mailer,
# request, channel, event, notifier, policy, config, facade, job,
# validator, middleware, decorator, engine, resource,
# transform, adapter, traits/paginated, bit/*) are unported design
# drafts — they lean on Ruby-isms (define_method, method_missing,
# instance_eval, **kwargs, &., Time.now) that Tungsten does not have,
# and have never run. They are not loaded. Realize one into the
# manifest above only after `bin/tungsten -c` passes on it AND it runs
# on both engines with spec coverage (see model.w for the porting
# pattern: top-level class, options hashes, flag-style flow).

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

# Pure-logic smoke checks over the routing + model + template core.
# Returns a list of failure messages (empty = healthy).
-> selftest_failures
  failures = []

  r = Route.new(:GET, "/users/:id", "UsersController", :show)
  failures.push("param route should match /users/42") unless r.match_path?("/users/42")
  failures.push("param route should not match /users") if r.match_path?("/users")
  failures.push("literal segment should not match /posts/42") if r.match_path?("/posts/42")
  failures.push("extract_params should capture :id") unless r.extract_params("/users/42")[:id] == "42"

  glob = Route.new(:GET, "/files/*path", "FilesController", :show)
  failures.push("glob route should match /files/a") unless glob.match_path?("/files/a")

  # Model + Serializer: create/find/where round-trip on the base Model.
  Model.reset_all
  rec = Model.create(Model, {name: "smoke"})
  failures.push("create should persist") unless rec.persisted?
  failures.push("find should round-trip") if Model.find(Model, rec.id) == nil
  failures.push("where should match attributes") unless Model.where(Model, {name: "smoke"}).size == 1
  blank_error = Model.new({}).validation_error(Model.presence(:name))
  failures.push("presence validation should flag a blank attribute") if blank_error == nil
  encoded = Serializer.record(rec)
  failures.push("serializer should encode the record") unless encoded.include?("\"id\":1") && encoded.include?("\"name\":\"smoke\"")
  Model.reset_all

  # Template engine: compile/render round-trip + escaping + error path.
  tpl = Template.compile("{{#each xs}}<li>{{this}}</li>{{/each}}")
  failures.push("template should compile") if tpl == nil
  if tpl != nil
    failures.push("template should render an escaped list") unless tpl.render({xs: ["a&b"]}) == "<li>a&amp;b</li>"
  failures.push("malformed template should compile to nil") unless Template.compile("{{#if x}}oops") == nil

  failures

# Run one recognized CLI command. carbide.w doubles as the bit manifest,
# so `use carbide` consumers execute this top-level call too — it
# therefore acts ONLY on a recognized first argument and is a silent
# no-op otherwise (a consumer's own argv — ports, file paths — must not
# be swallowed, and no am-I-the-main-program signal exists today).
# Consequence: bare `carbide` prints nothing; use `carbide help`.
-> run_cli(args)
  cmd = nil
  cmd = args[0] if args.size > 0

  if cmd == "version" || cmd == "--version" || cmd == "-v"
    << "Tungsten Carbide [VERSION]"
  elsif cmd == "selftest"
    failures = selftest_failures
    if failures.empty?
      << "PASS — routing + model + template core healthy"
    else
      failures.each -> (f)
        << "FAIL: [f]"
      exit(1)
  elsif cmd == "help" || cmd == "--help" || cmd == "-h"
    print_usage

run_cli(argv())
