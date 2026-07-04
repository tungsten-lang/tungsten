# Forge::Bench::Runner — benchmark harness
# Simple HTTP load testing for measuring Forge performance

in Tungsten:Forge:Bench

+ Runner
  ro :url
  ro :connections
  ro :duration
  ro :results

  -> new(url:, connections: 64, duration: 10)
    @url         = url
    @connections  = connections
    @duration     = duration
    @results      = nil

  -> run
    Logger.info("Benchmarking [@url]")
    Logger.info("  Connections: [@connections]")
    Logger.info("  Duration: [@duration]s")

    start = Time.monotonic
    total_requests = Atomic.new(0)
    total_errors = Atomic.new(0)
    latencies = ConcurrentArray.new

    threads = @connections.times.map -> (i)
      Thread.new ->
        deadline = Time.monotonic + @duration
        while Time.monotonic < deadline
          req_start = Time.monotonic
          begin
            response = HTTP.get(@url)
            latency = Time.monotonic - req_start
            latencies.push(latency)
            total_requests.increment
            if response.status >= 400
              total_errors.increment
          rescue error
            total_errors.increment

    threads.each -> (t) t.join

    elapsed = Time.monotonic - start
    sorted = latencies.to_a.sort

    @results = {
      total_requests: total_requests.get,
      total_errors: total_errors.get,
      requests_per_sec: (total_requests.get / elapsed).round(0),
      elapsed: elapsed.round(2),
      latency_avg: self.average(sorted),
      latency_p50: self.percentile(sorted, 50),
      latency_p90: self.percentile(sorted, 90),
      latency_p99: self.percentile(sorted, 99),
      latency_max: sorted.last
    }

    self.print_results
    @results

  -> print_results
    r = @results
    Logger.info("Results:")
    Logger.info("  Requests:     [r[:total_requests]]")
    Logger.info("  Errors:       [r[:total_errors]]")
    Logger.info("  Req/sec:      [r[:requests_per_sec]]")
    Logger.info("  Elapsed:      [r[:elapsed]]s")
    Logger.info("  Latency:")
    Logger.info("    Avg:  [self.format_latency(r[:latency_avg])]")
    Logger.info("    P50:  [self.format_latency(r[:latency_p50])]")
    Logger.info("    P90:  [self.format_latency(r[:latency_p90])]")
    Logger.info("    P99:  [self.format_latency(r[:latency_p99])]")
    Logger.info("    Max:  [self.format_latency(r[:latency_max])]")

  -> average(sorted)
    return 0 if sorted.empty?
    sorted.sum / sorted.size

  -> percentile(sorted, pct)
    return 0 if sorted.empty?
    idx = ((pct / 100.0) * sorted.size).ceil - 1
    sorted[[idx, 0].max]

  -> format_latency(seconds)
    case seconds
      s if s < 0.001 => "[(s * 1_000_000).round]µs"
      s if s < 1.0   => "[(s * 1000).round(2)]ms"
      => "[seconds.round(2)]s"
