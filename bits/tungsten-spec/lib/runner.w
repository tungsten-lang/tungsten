# Spec::Runner — discovers, orders, and executes spec files
# Reports results via pluggable formatters.

in Tungsten:Spec

+ Runner
  ro :config
  ro :results

  @@contexts = []

  -> .register(context)
    @@contexts.push(context)

  -> .reset
    @@contexts = []

  -> new(@config)
    @results   = []
    @formatter = resolve_formatter(@config.format)

  -> run
    contexts = @@contexts
    contexts = filter_by_tags(contexts) if @config.filter_tags.any?

    # Randomize order if seed is set
    if @config.seed
      Random.seed(@config.seed)
      contexts = contexts.shuffle

    @formatter.start(contexts)

    contexts.each -> (ctx)
      run_context(ctx)

    @formatter.finish(@results)

    # Return summary
    Summary.new(@results)

  -> run_context(ctx)
    # Run before_all hooks
    ctx.collected_hooks(:before_all).each(h -> h.call)

    # Run each example
    ctx.examples.each -> (example)
      run_example(ctx, example)

    # Recurse into children
    ctx.children.each -> (child)
      run_context(child)

    # Run after_all hooks
    ctx.collected_hooks(:after_all).each(h -> h.call)

  -> run_example(ctx, example)
    # Build execution environment with let bindings
    env = ExampleEnvironment.new(ctx.collected_lets)

    # Run before_each hooks
    ctx.collected_hooks(:before_each).each(h -> env.instance_eval(&h))

    # Run the example
    result = example.run(env)
    @results.push(result)

    @formatter.report(result)

    # Bail on first failure if configured
    if result.failed? && @config.fail_fast
      @formatter.finish(@results)
      exit 1

    # Run after_each hooks
    ctx.collected_hooks(:after_each).each(h -> env.instance_eval(&h))

  -> filter_by_tags(contexts)
    contexts.select -> (ctx)
      @config.filter_tags.any?(tag -> ctx.tags.include?(tag))

  -> resolve_formatter(format)
    case format
      :dots => DotsFormatter.new(@config.color)
      :doc  => DocFormatter.new(@config.color)
      :json => JsonFormatter.new
      =>      DotsFormatter.new(@config.color)


# Environment for running examples — provides let bindings
+ ExampleEnvironment
  -> new(lets)
    @lets    = lets
    @memo    = {}

  -> method_missing(name, *args)
    if @lets.has_key?(name)
      @memo[name] ||= instance_eval(&@lets[name])
    else
      super


# --- Formatters ---

+ DotsFormatter
  -> new(@color)

  -> start(contexts)
    # nothing

  -> report(result)
    case result.status
      :passed  => <- colorize(".", :green)
      :failed  => <- colorize("F", :red)
      :pending => <- colorize("*", :yellow)
      :skipped => <- colorize("-", :cyan)

  -> finish(results)
    << ""
    << ""

    # Print failures
    failures = results.select(r -> r.failed?)
    if failures.any?
      << "Failures:\n"
      failures.each_with_index -> (result, i)
        << "  #{i + 1}) #{result.description}"
        << "     #{colorize(result.error.message, :red)}"
        << ""

    # Print summary line
    total   = results.size
    passed  = results.count(r -> r.passed?)
    failed  = results.count(r -> r.failed?)
    pending = results.count(r -> r.pending?)

    summary = "#{total} examples, #{failed} failures"
    summary += ", #{pending} pending" if pending > 0
    color = if failed > 0 then :red else :green
    << colorize(summary, color)

  -> colorize(text, color)
    return text unless @color
    code = case color
      :red    => "31"
      :green  => "32"
      :yellow => "33"
      :cyan   => "36"
      =>        "0"
    "\e[#{code}m#{text}\e[0m"


+ DocFormatter
  -> new(@color)
    @indent = 0

  -> start(contexts)
    # nothing

  -> report(result)
    prefix = "  " * @indent
    case result.status
      :passed  => << "#{prefix}#{result.description}"
      :failed  => << "#{prefix}#{result.description} (FAILED)"
      :pending => << "#{prefix}#{result.description} (PENDING)"
      :skipped => << "#{prefix}#{result.description} (SKIPPED)"

  -> finish(results)
    << ""
    total  = results.size
    failed = results.count(r -> r.failed?)
    << "#{total} examples, #{failed} failures"


+ JsonFormatter
  -> start(contexts) = nil
  -> report(result)  = nil

  -> finish(results)
    data = results.map -> (r)
      {description: r.description, status: r.status, error: r.error&.message}
    << data |> JSON.encode


# Summary of a spec run
+ Summary
  ro :results

  -> new(@results)

  -> total     = @results.size
  -> passed    = @results.count(r -> r.passed?)
  -> failed    = @results.count(r -> r.failed?)
  -> pending   = @results.count(r -> r.pending?)
  -> exit_code = if failed > 0 then 1 else 0
  -> success?  = failed == 0
