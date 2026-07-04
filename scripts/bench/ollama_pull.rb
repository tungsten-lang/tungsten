#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

$stdout.sync = true
$stderr.sync = true

model = ARGV.fetch(0) do
  warn "usage: ruby scripts/bench/ollama_pull.rb MODEL"
  exit 2
end

def ollama_base_uri
  host = ENV.fetch("OLLAMA_HOST", "http://127.0.0.1:11434")
  host = "http://#{host}" unless host.start_with?("http://", "https://")
  URI(host)
end

def human_bytes(bytes)
  value = bytes.to_f
  units = %w[B KB MB GB TB]
  unit = units.shift
  while value >= 1024.0 && !units.empty?
    value /= 1024.0
    unit = units.shift
  end
  format("%.1f %s", value, unit)
end

def progress_line(event)
  status = event["status"].to_s
  completed = event["completed"].to_i
  total = event["total"].to_i
  return status if total <= 0

  pct = (completed * 100.0 / total)
  "#{status}: #{format("%.1f", pct)}% (#{human_bytes(completed)} / #{human_bytes(total)})"
end

uri = ollama_base_uri
uri.path = "/api/pull"

http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = uri.scheme == "https"
http.open_timeout = 10
http.read_timeout = Integer(ENV.fetch("OLLAMA_PULL_READ_TIMEOUT", "7200"))

request = Net::HTTP::Post.new(uri)
request["Content-Type"] = "application/json"
request.body = JSON.generate(model: model, stream: true)

puts "pulling #{model} from #{uri}"
last_print_at = Time.at(0)
last_line = nil

http.request(request) do |response|
  unless response.is_a?(Net::HTTPSuccess)
    body = response.body
    begin
      body = JSON.parse(body).fetch("error", body)
    rescue JSON::ParserError
      nil
    end
    raise "#{response.code} #{response.message}: #{body}"
  end

  response.read_body do |chunk|
    chunk.each_line do |line|
      next if line.strip.empty?

      event = JSON.parse(line)
      raise event["error"] if event["error"]

      now = Time.now
      rendered = progress_line(event)
      done = event["status"] == "success"
      should_print = done || rendered != last_line && now - last_print_at >= 30

      if should_print
        puts rendered
        last_line = rendered
        last_print_at = now
      end
    end
  end
end
