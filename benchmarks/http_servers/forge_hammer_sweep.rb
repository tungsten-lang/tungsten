#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "open3"
require "optparse"

ROOT = File.expand_path("../..", __dir__)

options = {
  port: 18_105,
  duration: 5,
  repeats: 1,
  forge_workers: [6],
  hammer_workers: [3],
  connections: 80,
  connection_counts: [80],
  depth: 512,
  depths: [512],
  tungsten: true,
  mode: nil,
}

def parse_list(value)
  if value.include?("..")
    first, last = value.split("..", 2).map(&:to_i)
    (first..last).to_a
  else
    value.split(",").map(&:to_i)
  end
end

OptionParser.new do |opts|
  opts.banner = "Usage: ruby benchmarks/http_servers/forge_hammer_sweep.rb MODE [options]"
  opts.separator ""
  opts.separator "Modes: workers, depth, connections"
  opts.separator ""

  opts.on("--port N", Integer, "Forge port") { |v| options[:port] = v }
  opts.on("-d", "--duration N", Integer, "Hammer run duration in seconds") { |v| options[:duration] = v }
  opts.on("--repeats N", Integer, "Repeats per point") { |v| options[:repeats] = v }
  opts.on("--forge LIST", "Forge workers, e.g. 1..10 or 4,6,8") { |v| options[:forge_workers] = parse_list(v) }
  opts.on("--hammer LIST", "Hammer workers, e.g. 1..6 or 3,4") { |v| options[:hammer_workers] = parse_list(v) }
  opts.on("-c", "--connections N", Integer, "Fixed connection count") { |v| options[:connections] = v }
  opts.on("--connection-counts LIST", "Connection counts for connections mode") do |v|
    options[:connection_counts] = parse_list(v)
  end
  opts.on("-b", "--depth N", Integer, "Fixed pipeline depth") { |v| options[:depth] = v }
  opts.on("--depths LIST", "Pipeline depths for depth mode") { |v| options[:depths] = parse_list(v) }
  opts.on("--c-hammer", "Use the C Hammer engine instead of Tungsten Hammer") { options[:tungsten] = false }
end.parse!(ARGV)
options[:mode] = ARGV.shift || "workers"

$forge_pid = nil

def wait_for_server(port, timeout: 60)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    begin
      http = Net::HTTP.new("127.0.0.1", port)
      http.open_timeout = 0.25
      http.read_timeout = 0.25
      return true if http.get("/").code.to_i == 200
    rescue StandardError
      sleep 0.1
    end
  end
  false
end

def start_forge(workers, port)
  log = "/tmp/tungsten-forge-sweep-w#{workers}.log"
  pid = Process.spawn(
    { "NO_COLOR" => "1" },
    "bin/tungsten", "forge", "--max", "-w", workers.to_s, "-p", port.to_s,
    chdir: ROOT,
    out: log,
    err: log,
  )
  $forge_pid = pid

  return pid if wait_for_server(port)

  warn "Forge failed to start for -w #{workers}; log follows"
  warn File.read(log) if File.exist?(log)
  Process.kill("TERM", pid) rescue nil
  Process.wait(pid) rescue nil
  exit 1
end

def stop_forge(pid = $forge_pid)
  return unless pid

  Process.kill("INT", pid) rescue nil
  50.times do
    begin
      waited = Process.wait(pid, Process::WNOHANG)
      if waited
        $forge_pid = nil if pid == $forge_pid
        return
      end
    rescue Errno::ECHILD
      $forge_pid = nil if pid == $forge_pid
      return
    end
    sleep 0.1
  end
  Process.kill("TERM", pid) rescue nil
  Process.wait(pid) rescue nil
  $forge_pid = nil if pid == $forge_pid
end

Signal.trap("INT") { stop_forge; exit 130 }
Signal.trap("TERM") { stop_forge; exit 143 }

def run_hammer(port:, duration:, hammer_workers:, connections:, depth:, tungsten:)
  cmd = [
    "bits/tungsten-hammer/bin/hammer", "--max",
    "-c", connections.to_s,
    "-d", duration.to_s,
    "-w", hammer_workers.to_s,
    "-p", "h11",
    "-b", depth.to_s,
    "http://127.0.0.1:#{port}/",
  ]
  cmd.insert(2, "--tungsten") if tungsten

  out, err, status = Open3.capture3(*cmd, chdir: ROOT)
  text = out + err
  rps = text[%r{req/sec:\s+([0-9.eE+-]+)}, 1]&.to_f
  requests = text[/requests:\s+(\d+)/, 1]&.to_i
  requests ||= parse_hammer_count(text[/(\d+(?:\.\d+)?[KMG]?) requests in/, 1])
  errors = text[/errors:\s+(\d+)/, 1]&.to_i || 0

  unless status.success? && rps
    warn "Hammer failed: #{cmd.join(' ')}"
    warn text
  end

  { rps: rps || 0.0, requests: requests || 0, errors: errors, ok: status.success? && !!rps }
end

def parse_hammer_count(value)
  return nil unless value

  multiplier =
    case value[-1]
    when "K" then 1_000.0
    when "M" then 1_000_000.0
    when "G" then 1_000_000_000.0
    else 1.0
    end
  (value.sub(/[KMG]\z/, "").to_f * multiplier).to_i
end

def median_summary(rows, key)
  rows.group_by { |row| row[key] }.map do |value, group|
    vals = group.map { |row| row[:rps] }.sort
    [value, vals.first, vals[vals.length / 2], vals.last]
  end.sort_by(&:first)
end

def print_summary(label, rows, key)
  puts "#{label} #{key},min,median,max"
  median_summary(rows, key).each do |value, min, median, max|
    puts [value, format("%.0f", min), format("%.0f", median), format("%.0f", max)].join(",")
  end
end

case options[:mode]
when "workers"
  puts "worker_sweep engine=#{options[:tungsten] ? 'tungsten' : 'c'} " \
       "forge=#{options[:forge_workers].join(',')} hammer=#{options[:hammer_workers].join(',')} " \
       "connections=#{options[:connections]} depth=#{options[:depth]} duration=#{options[:duration]}s"
  puts "forge_w,hammer_w,depth,connections,repeat,req_per_sec,requests,errors,ok"

  rows = []
  options[:forge_workers].each do |forge_workers|
    pid = start_forge(forge_workers, options[:port])
    sleep 0.5
    options[:hammer_workers].each do |hammer_workers|
      options[:repeats].times do |i|
        result = run_hammer(
          port: options[:port],
          duration: options[:duration],
          hammer_workers: hammer_workers,
          connections: options[:connections],
          depth: options[:depth],
          tungsten: options[:tungsten],
        )
        row = { forge_workers: forge_workers, hammer_workers: hammer_workers, repeat: i + 1, **result }
        rows << row
        puts [
          forge_workers, hammer_workers, options[:depth], options[:connections], i + 1,
          format("%.0f", result[:rps]), result[:requests], result[:errors], result[:ok],
        ].join(",")
        STDOUT.flush
      end
    end
  ensure
    stop_forge(pid) if pid
    sleep 0.5
  end

  best = rows.max_by { |row| row[:rps] }
  puts "best_workers forge_w=#{best[:forge_workers]} hammer_w=#{best[:hammer_workers]} " \
       "req_per_sec=#{format('%.0f', best[:rps])}"
when "depth"
  forge_workers = options[:forge_workers].first
  hammer_workers = options[:hammer_workers].first
  rows = []
  pid = start_forge(forge_workers, options[:port])
  begin
    sleep 0.5
    puts "depth_sweep engine=#{options[:tungsten] ? 'tungsten' : 'c'} forge_w=#{forge_workers} " \
         "hammer_w=#{hammer_workers} connections=#{options[:connections]} duration=#{options[:duration]}s"
    puts "depth,repeat,req_per_sec,requests,errors,ok"
    options[:depths].each do |depth|
      options[:repeats].times do |i|
        result = run_hammer(
          port: options[:port],
          duration: options[:duration],
          hammer_workers: hammer_workers,
          connections: options[:connections],
          depth: depth,
          tungsten: options[:tungsten],
        )
        rows << { depth: depth, repeat: i + 1, **result }
        puts [depth, i + 1, format("%.0f", result[:rps]), result[:requests], result[:errors], result[:ok]].join(",")
        STDOUT.flush
        sleep 0.25
      end
    end
    print_summary("depth_summary", rows, :depth)
  ensure
    stop_forge(pid) if pid
  end
when "connections"
  forge_workers = options[:forge_workers].first
  hammer_workers = options[:hammer_workers].first
  rows = []
  pid = start_forge(forge_workers, options[:port])
  begin
    sleep 0.5
    puts "connection_sweep engine=#{options[:tungsten] ? 'tungsten' : 'c'} forge_w=#{forge_workers} " \
         "hammer_w=#{hammer_workers} depth=#{options[:depth]} duration=#{options[:duration]}s"
    puts "connections,repeat,req_per_sec,requests,errors,ok"
    options[:connection_counts].each do |connections|
      options[:repeats].times do |i|
        result = run_hammer(
          port: options[:port],
          duration: options[:duration],
          hammer_workers: hammer_workers,
          connections: connections,
          depth: options[:depth],
          tungsten: options[:tungsten],
        )
        rows << { connections: connections, repeat: i + 1, **result }
        puts [connections, i + 1, format("%.0f", result[:rps]), result[:requests], result[:errors], result[:ok]].join(",")
        STDOUT.flush
        sleep 0.25
      end
    end
    print_summary("connection_summary", rows, :connections)
  ensure
    stop_forge(pid) if pid
  end
else
  warn "Unknown mode: #{options[:mode]}"
  warn "Expected workers, depth, or connections"
  exit 1
end
