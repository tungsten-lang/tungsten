require "net/http"
require "json"
require "uri"

module Tungsten
  class AI
    RESET      = "\e[0m"
    BOLD       = "\e[1m"
    DIM        = "\e[2m"
    CYAN       = "\e[36m"
    MAGENTA    = "\e[35m"
    BRIGHT_RED = "\e[91m"

    SYSTEM_PROMPT = <<~PROMPT
      You are a Tungsten programming language expert. Write valid Tungsten code.

      Key syntax:
      - `<< expr` prints to stdout
      - `-> name(args)` defines a method
      - `fn name(args)` defines a pure function
      - `+ ClassName` defines a class
      - `trait Name` defines a trait, `is TraitName` includes it
      - Indentation-based blocks (2 spaces)
      - `[expr]` for string interpolation
      - `if/elsif/else`, `while`, `case/when`
      - `ro :field` (getter), `rw :field` (getter+setter)
      - Arrays: `[1, 2, 3]`, Hashes: `{key: value}`
      - Ranges: `1..10`, `1...10` (exclusive)

      Output ONLY the Tungsten code, no markdown fences or explanation.
    PROMPT

    def initialize
      @color = $stdout.tty? && !ENV["NO_COLOR"]
      @api_key = ENV["ANTHROPIC_API_KEY"]
    end

    def run(prompt)
      unless @api_key
        $stderr.puts "#{c(BRIGHT_RED)}✗#{c(RESET)} Missing ANTHROPIC_API_KEY. Set it: export ANTHROPIC_API_KEY=sk-..."
        exit 1
      end

      if prompt.nil? || prompt.strip.empty?
        $stderr.puts "Usage: tungsten ai 'describe what you want'"
        exit 1
      end

      $stderr.print "#{c(DIM)}✳ Forging...#{c(RESET)}"

      code = call_api(prompt)

      $stderr.puts "\r#{" " * 20}\r"
      puts "#{c(DIM)}──#{c(RESET)}"
      puts code
      puts "#{c(DIM)}──#{c(RESET)}"
      puts

      $stdout.flush
      $stderr.print "#{c(MAGENTA)}Run this? (y/n) #{c(RESET)}"
      answer = $stdin.gets&.strip&.downcase

      if answer == "y"
        puts
        Interpreter.new.run(code)
      end
    end

    private

    def call_api(prompt)
      uri = URI("https://api.anthropic.com/v1/messages")
      response = Net::HTTP.post(uri, {
        model: "claude-sonnet-4-20250514",
        max_tokens: 2048,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: prompt }]
      }.to_json, {
        "Content-Type"      => "application/json",
        "x-api-key"         => @api_key,
        "anthropic-version" => "2023-06-01"
      })

      raise Error, "API error (#{response.code}): #{response.body}" unless response.code == "200"

      begin
        JSON.parse(response.body)["content"][0]["text"].strip
      rescue JSON::ParserError => e
        raise Error, "JSON parsing error: #{e.message}"
      end
    end

    def c(code)
      @color ? code : ""
    end
  end
end
