#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

DEFAULT_MODELS = [
  "qwen3.6:35b-a3b-nvfp4",
  "qwen3.6:35b-a3b-mxfp8"
].freeze

PROMPT = ENV.fetch("PROMPT", "The capital of France is")
NUM_PREDICT = Integer(ENV.fetch("NUM_PREDICT", "50"))
WARMUPS = Integer(ENV.fetch("WARMUPS", "1"))
RUNS = Integer(ENV.fetch("RUNS", "5"))

def ollama_base_uri
  host = ENV.fetch("OLLAMA_HOST", "http://127.0.0.1:11434")
  host = "http://#{host}" unless host.start_with?("http://", "https://")
  URI(host)
end

def post_json(path, payload)
  uri = ollama_base_uri
  uri.path = path

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.open_timeout = 10
  http.read_timeout = 600

  request = Net::HTTP::Post.new(uri)
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(payload)

  response = http.request(request)
  body = JSON.parse(response.body)
  return body if response.is_a?(Net::HTTPSuccess)

  raise "#{response.code} #{response.message}: #{body.fetch("error", response.body)}"
end

def ns_to_s(ns)
  ns.to_f / 1_000_000_000.0
end

def tokens_per_second(count, duration_ns)
  seconds = ns_to_s(duration_ns)
  return 0.0 if count.to_i <= 0 || seconds <= 0.0

  count.to_f / seconds
end

def mean(values)
  values.sum / values.length.to_f
end

def median(values)
  sorted = values.sort
  mid = sorted.length / 2
  sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
end

def summarize(label, values)
  return "#{label}=n/a" if values.empty?

  "#{label}=min %.2f mean %.2f median %.2f max %.2f" % [
    values.min,
    mean(values),
    median(values),
    values.max
  ]
end

def generate_once(model)
  post_json(
    "/api/generate",
    {
      model: model,
      prompt: PROMPT,
      stream: false,
      keep_alive: "30m",
      options: {
        num_predict: NUM_PREDICT,
        temperature: 0,
        top_k: 1,
        seed: 1
      }
    }
  )
end

models = ARGV.empty? ? DEFAULT_MODELS : ARGV

puts "Ollama MLX/GGML benchmark"
puts "host=#{ollama_base_uri} prompt=#{PROMPT.inspect} num_predict=#{NUM_PREDICT} warmups=#{WARMUPS} runs=#{RUNS}"

models.each do |model|
  puts
  puts "model=#{model}"

  begin
    WARMUPS.times do |i|
      result = generate_once(model)
      prompt_tps = tokens_per_second(result["prompt_eval_count"], result["prompt_eval_duration"])
      decode_tps = tokens_per_second(result["eval_count"], result["eval_duration"])
      puts "  warmup #{i + 1}/#{WARMUPS}: prompt %.2f tok/s, decode %.2f tok/s, load %.3f s" % [
        prompt_tps,
        decode_tps,
        ns_to_s(result["load_duration"])
      ]
    end

    prompt_rates = []
    decode_rates = []
    total_times = []

    RUNS.times do |i|
      result = generate_once(model)
      prompt_tps = tokens_per_second(result["prompt_eval_count"], result["prompt_eval_duration"])
      decode_tps = tokens_per_second(result["eval_count"], result["eval_duration"])
      total_s = ns_to_s(result["total_duration"])

      prompt_rates << prompt_tps if prompt_tps.positive?
      decode_rates << decode_tps if decode_tps.positive?
      total_times << total_s if total_s.positive?

      puts "  run #{i + 1}/#{RUNS}: prompt %.2f tok/s (%d toks), decode %.2f tok/s (%d toks), total %.3f s" % [
        prompt_tps,
        result["prompt_eval_count"].to_i,
        decode_tps,
        result["eval_count"].to_i,
        total_s
      ]
    end

    puts "  summary: #{summarize("prompt", prompt_rates)}"
    puts "           #{summarize("decode", decode_rates)}"
    puts "           #{summarize("total_s", total_times)}"
  rescue StandardError => e
    warn "  error: #{e.message}"
  end
end
