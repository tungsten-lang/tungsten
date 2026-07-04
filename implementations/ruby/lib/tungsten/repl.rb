# frozen_string_literal: true

require "reline"
require "stringio"
require "bigdecimal"
require "date"
require "io/console"
require "net/http"
require "json"
require "open3"
require "shellwords"
require "timeout"
require "tty-markdown"

module Tungsten
  # Translates kitty keyboard protocol (CSI u) sequences back to legacy
  # bytes so Reline can understand them. Shift+Enter becomes byte 30 (RS),
  # which we bind to ed_force_submit.
  class KittyFilter
    RS = 30 # Record Separator — unused ASCII byte we map Shift+Enter to

    def initialize(io)
      @io = io
      @buf = []
    end

    def getbyte
      return @buf.shift unless @buf.empty?

      b = @io.getbyte
      return b unless b == 0x1B # ESC

      # Peek for CSI u: \e [ digits (;digits)? u
      c = @io.getbyte
      unless c == 0x5B # '['
        @buf << c if c
        return b
      end

      seq = +""
      while (ch = @io.getbyte)
        if ch == 0x75 # 'u'
          return translate(seq)
        elsif (ch >= 0x30 && ch <= 0x39) || ch == 0x3B # digit or ';'
          seq << ch.chr
        else
          # Not a CSI u sequence — push what we consumed back
          @buf.concat([0x5B] + seq.bytes + [ch])
          return b
        end
      end
      b
    end

    def raw(*)  = @io.raw(*)  if @io.respond_to?(:raw)

    def wait_readable(*args)
      return @io if @buf.any?

      @io.wait_readable(*args) if @io.respond_to?(:wait_readable)
    end

    # Delegate everything else to the underlying IO
    def respond_to_missing?(m, include_private = false) = @io.respond_to?(m, include_private)
    def method_missing(m, ...) = @io.respond_to?(m) ? @io.send(m, ...) : super

    private

    def translate(seq)
      parts = seq.split(";")
      codepoint = parts[0].to_i
      modifiers = parts[1]&.to_i || 1

      if codepoint == 13 && modifiers == 2 # Shift+Enter
        RS
      elsif modifiers == 5 # Ctrl+key
        if codepoint >= 65 && codepoint <= 90       # Ctrl+uppercase
          codepoint - 64
        elsif codepoint >= 97 && codepoint <= 122    # Ctrl+lowercase
          codepoint - 96
        else
          push_original(seq)
        end
      elsif modifiers >= 2 # Other modifier — drop modifier, emit codepoint
        push_codepoint(codepoint)
      else # Plain disambiguated key
        push_codepoint(codepoint)
      end
    end

    def push_codepoint(cp)
      encoded = [cp].pack("U").bytes
      @buf.concat(encoded[1..]) if encoded.size > 1
      encoded[0]
    end

    def push_original(seq)
      @buf.concat([0x5B] + seq.bytes + [0x75])
      0x1B
    end
  end

  module CyclingHistory
    private

    def ed_prev_history(key, arg: 1)
      sanitize_reline_history!
      if @line_index > 0
        cursor = current_byte_pointer_cursor
        @line_index -= 1
        calculate_nearest_cursor(cursor)
        return
      end
      return if Reline::HISTORY.empty?

      move_history(
        @history_pointer.nil? ? Reline::HISTORY.size - 1 : ((@history_pointer - 1) % Reline::HISTORY.size),
        line: :end,
        cursor: @config.editing_mode_is?(:vi_command) ? :start : :end,
      )
      arg -= 1
      ed_prev_history(key, arg: arg) if arg > 0
    end

    def ed_next_history(key, arg: 1)
      sanitize_reline_history!
      if @line_index < (@buffer_of_lines.size - 1)
        cursor = current_byte_pointer_cursor
        @line_index += 1
        calculate_nearest_cursor(cursor)
        return
      end
      return if Reline::HISTORY.empty?

      move_history(
        @history_pointer.nil? ? 0 : ((@history_pointer + 1) % Reline::HISTORY.size),
        line: :start,
        cursor: @config.editing_mode_is?(:vi_command) ? :start : :end,
      )
      arg -= 1
      ed_next_history(key, arg: arg) if arg > 0
    end

    def sanitize_reline_history!
      Reline::HISTORY.delete_if { |entry| entry.to_s.strip == "!" }
    end
  end

  module InstantShellMode
    private

    def ed_insert(str)
      if str == "!" && current_line.empty? && @byte_pointer.zero?
        repl = Thread.current[:tungsten_wit_repl]
        if repl&.send(:activate_shell_mode_from_bang)
          refresh_tungsten_prompt!(repl)
          return
        end
      end

      super
    end
    alias_method :self_insert, :ed_insert

    def em_delete_prev_char(key, arg: 1)
      if current_line.empty? && @byte_pointer.zero?
        repl = Thread.current[:tungsten_wit_repl]
        if repl&.send(:cancel_shell_mode_from_backspace)
          refresh_tungsten_prompt!(repl)
          return
        end
      end

      super
    end

    def refresh_tungsten_prompt!(repl)
      repl.send(:refresh_prompt_frame)
      @prompt = repl.send(:prompt).gsub("\n", "\\n")
      @cache.clear if defined?(@cache) && @cache
    end
  end

  class REPL
    SPINNER = %w[· ✢ ✳ ✻ ✽].freeze

    VERBS = %w[
      Smelting Forging Alloying Tempering
      Annealing Casting Quenching Refining
    ].freeze

    KEYWORDS = %w[
      if else elsif while until with case when
      module return break next continue
      true false nil
      begin rescue ensure raise
      use self super yield unless trait
      always redo retry in
    ].freeze

    # Block-opening keywords that expect an indented body
    BLOCK_OPENERS = %w[if elsif else while until with module begin rescue ensure case when unless always].freeze

    # Keywords that close one block and open another at the same level as their opener
    DEDENT_KEYWORDS = %w[else elsif rescue ensure when].freeze

    REPO_ROOT = File.expand_path("../../../..", __dir__)
    LOCAL_MODEL_READY_TIMEOUT = 90
    LOCAL_MODEL_RESPONSE_TIMEOUT = 300
    LOCAL_MODEL_PROMPT_DIRECTIVES = {
      "a" => "Write an article on:",
      "p" => "Answer in one paragraph.",
      "s" => "Answer in one short sentence.",
      "w" => "Answer in one word."
    }.freeze
    AIKU_PROMPT_PREFIX = "Answer like a chechen warrior writing an informational one-pager. " \
                         "Somewhere between CIA fact-book and tomato-growing variety overview. " \
                         "End your response with a haiku. The topic is: "

    MODELS = {
      "haiku"  => { provider: :anthropic, id: "claude-haiku-4-5-20251001", label: "Claude Haiku 4.5  (fast)" },
      "sonnet" => { provider: :anthropic, id: "claude-sonnet-4-6",         label: "Claude Sonnet 4.6 (default)" },
      "opus"   => { provider: :anthropic, id: "claude-opus-4-6",           label: "Claude Opus 4.6  (powerful)" },
      "lightning" => {
        provider: :local,
        id: "lightning",
        label: "Lightning-1.7B local",
        command: [File.join(REPO_ROOT, "bits/tungsten-llama/bin/llama"), "serve", "lightning"]
      }
    }.freeze
    DEFAULT_AI_MODEL = "sonnet"

    # ANSI
    RESET  = "\e[0m"
    BOLD   = "\e[1m"
    DIM    = "\e[2m"
    RED    = "\e[31m"
    GREEN  = "\e[32m"
    YELLOW = "\e[33m"
    CYAN   = "\e[36m"
    MAGENTA = "\e[35m"
    WHITE  = "\e[37m"
    BRIGHT_RED     = "\e[91m"
    BRIGHT_MAGENTA = "\e[95m"
    BRIGHT_CYAN    = "\e[96m"
    BRIGHT_YELLOW  = "\e[93m"

    def initialize
      @interpreter = Interpreter.new
      @history_file = File.expand_path("~/.tungsten_history")
      @tty = $stdout.tty?
      @session_log = []
      @ai_model = DEFAULT_AI_MODEL
      @shell_mode = false
      @shell_mode_one_shot = false
      @shell_mode_backspace_cancel = false
      @shell_cwd = Dir.pwd
      @previous_shell_cwd = nil
      @model_servers = {}
    end

    def start
      setup_readline
      load_history
      print_banner
      repl_loop
    ensure
      stop_all_model_servers
      save_history
      if @kitty_enabled
        print "\e[<u"
        $stdout.flush
      end
      puts "#{RESET}"
    end

    private

    # ── Terminal helpers ──────────────────────────────────────────────

    def terminal_size
      IO.console&.winsize || [24, 80]
    end

    def prompt_rule_color
      @shell_mode ? YELLOW : DIM
    end

    # Print a thin separator above the prompt.
    def print_separator
      return unless @tty

      _, cols = terminal_size
      puts "#{prompt_rule_color}#{"─" * cols}#{RESET}"
    end

    # Print a separator + hint below the submitted input.
    def print_bottom_separator
      return unless @tty

      _, cols = terminal_size
      puts "#{prompt_rule_color}#{"─" * cols}#{RESET}"
      puts "#{DIM}#{prompt_hint}#{RESET}"
    end

    # Pre-print the bottom HR + hint below where the prompt will render, then
    # move the cursor back up so Reline renders the prompt in the right place.
    # This makes the footer visible while the user is typing.
    def print_prompt_footer
      return unless @tty

      _, cols = terminal_size
      puts ""                                        # blank — prompt will render here
      puts "#{prompt_rule_color}#{"─" * cols}#{RESET}" # bottom HR
      puts "#{DIM}#{prompt_hint}#{RESET}"                  # hint
      print "\e[3A\r"                               # move cursor back up to prompt line
      $stdout.flush
    end

    def refresh_prompt_frame
      return unless @tty

      _, cols = terminal_size
      rule = "#{prompt_rule_color}#{"─" * cols}#{RESET}"
      hint = "#{DIM}#{prompt_hint}#{RESET}"
      print "\e7"             # save cursor on the prompt line
      print "\r\e[1A\e[2K#{rule}"
      print "\r\e[2B\e[2K#{rule}"
      print "\r\e[1B\e[2K#{hint}"
      print "\e8"             # restore cursor for Reline's next render
      $stdout.flush
    end

    def print_shortcuts
      puts "#{BOLD}Shortcuts:#{RESET}"
      puts "  #{DIM}Ctrl+D      #{RESET}  exit"
      puts "  #{DIM}Shift+Enter #{RESET}  submit multi-line block"
      puts "  #{DIM}Tab         #{RESET}  show completions for names, methods, units, and paths"
      puts "  #{DIM}↑ / ↓       #{RESET}  browse history"
      puts "  #{DIM}@ai …       #{RESET}  ask AI inline (current model: #{@ai_model})"
      puts "  #{DIM}@claude …   #{RESET}  ask Claude (sonnet) inline"
      puts "  #{DIM}/model      #{RESET}  show or switch AI model"
      puts "  #{DIM}!           #{RESET}  run one command from a transient shell prompt"
      puts "  #{DIM}! cmd       #{RESET}  run command, then return to wit"
      puts "  #{DIM}/paste      #{RESET}  paste verbatim Tungsten; finish with /end"
      puts "  #{DIM}?           #{RESET}  show this help"
      puts "  #{DIM}? expr      #{RESET}  inspect a value or raw WValue (example: ? u0xFFF9073656C6966B)"
    end

    def prompt_hint
      return "  shell command · returns to wit after Enter" if @shell_mode

      "  Tab completions  ·  ! shell  ·  ? inspect  ·  model: #{@ai_model}"
    end

    # After input is submitted, erase the separator line drawn above it.
    # Uses visual line count (strips trailing newlines Reline appends) to avoid
    # off-by-one errors when computing how far up to move.
    def erase_separator(input)
      return unless @tty

      visual_lines = [input.strip.lines.size, 1].max
      up = visual_lines + 1                 # visual input lines + HR line
      print "\e[#{up}A"                     # move up to HR line
      print "\e[2K"                         # erase HR
      print "\e[#{up}B\r"                   # move back down to original position
      $stdout.flush
    end

    # Erase any remnants below the cursor (status bar, etc).
    def clear_below
      return unless @tty

      print "\e[J"
      $stdout.flush
    end

    # ── Readline setup ────────────────────────────────────────────────

    def setup_readline
      Reline.completion_proc = method(:complete)
      Reline.autocompletion = true if Reline.respond_to?(:autocompletion=)
      Reline.completion_append_character = nil if Reline.respond_to?(:completion_append_character=)
      Reline.prompt_proc = proc { |lines|
        lines.map.with_index { |_, i| i == 0 ? prompt : continuation_prompt }
      }
      Reline.output_modifier_proc = proc { |text, complete:| decorate_input(text, complete:) }
      Reline.auto_indent_proc = method(:calc_indent)
      Reline::LineEditor.prepend(CyclingHistory) unless Reline::LineEditor < CyclingHistory
      Reline::LineEditor.prepend(InstantShellMode) unless Reline::LineEditor < InstantShellMode

      # Enable kitty keyboard protocol so Shift+Enter sends a distinct sequence.
      # KittyFilter translates CSI u sequences back to legacy bytes for Reline,
      # except Shift+Enter which maps to byte 30 (RS) → ed_force_submit.
      if $stdin.tty?
        @kitty_enabled = true
        print "\e[>1u"
        $stdout.flush
        Reline.core.io_gate.input = KittyFilter.new($stdin)
      end

      config = Reline.core.config
      [:emacs, :vi_insert].each do |keymap|
        config.add_default_key_binding_by_keymap(keymap, [KittyFilter::RS], :ed_force_submit)
      end

      # Override Ctrl+D behavior: clear line if there's text, EOF if empty.
      Reline::LineEditor.prepend(Module.new do
        private def em_delete(key)
          if buffer_empty? && key == "\C-d"
            @eof = true
            finish
          elsif !buffer_empty? && key == "\C-d"
            @buffer_of_lines = [+""]
            @line_index = 0
            set_current_line(+"", 0)
          else
            super
          end
        end
      end)
    end

    def load_history
      sanitize_history!
      return unless File.exist?(@history_file)

      File.readlines(@history_file, chomp: true).last(1000).each do |line|
        entry = line.gsub("\x1f", "\n")
        Reline::HISTORY << entry if persisted_history?(entry)
      end
      sanitize_history!
    rescue StandardError
      nil
    end

    def save_history
      sanitize_history!
      File.open(@history_file, "w") do |f|
        Reline::HISTORY.to_a.select { |entry| persisted_history?(entry) }.last(1000).each do |entry|
          f.puts(entry.gsub("\n", "\x1f"))
        end
      end
    rescue StandardError
      nil
    end

    def complete(input, pre = nil, _post = nil)
      input = input.to_s
      line = pre.nil? ? input : "#{pre}#{input}"
      stripped_line = line.lstrip

      if stripped_line.start_with?("/model")
        model_prefix = stripped_line.delete_prefix("/model").lstrip
        return MODELS.keys.select { |name| model_prefix.empty? || name.start_with?(model_prefix) }.sort
      end

      return [] if stripped_line.start_with?("@ai") || stripped_line.start_with?("@aiku")

      raw_prefix = input[/[[:alnum:]_?!\/.\-]+\z/].to_s
      return [] if raw_prefix.empty?
      return file_completions(raw_prefix) if @shell_mode || stripped_line.start_with?("!")

      prefix = completion_name_prefix(raw_prefix)
      name_matches = completion_name_matches(prefix, raw_prefix)
      file_matches = file_completion_prefix?(raw_prefix) ? file_completions(raw_prefix) : []
      (name_matches + file_matches).uniq.sort
    end

    def completion_name_prefix(raw_prefix)
      raw_prefix.to_s.split(/[\/.]/).last.to_s
    end

    def completion_name_matches(prefix, raw_prefix)
      return [] if raw_prefix.start_with?(".")

      (KEYWORDS + @interpreter.completion_names).uniq.select do |candidate|
        prefix.empty? || candidate.start_with?(prefix)
      end
    end

    def file_completion_prefix?(prefix)
      prefix.start_with?(".") || prefix.match?(%r{\A[\w.-]+/})
    end

    def file_completions(prefix)
      return [] unless prefix.include?("/") || prefix.start_with?(".")

      Dir.glob("#{prefix}*").map { |path| File.directory?(path) ? "#{path}/" : path }
    rescue StandardError
      []
    end

    def decorate_input(text, complete:)
      decorated = text.gsub(/@\S*/) do |match|
        # Valid: @lowercase_start — bright magenta (includes bare @ still being typed)
        # Invalid: @Uppercase or @digit-start — bright red
        color = match.length == 1 || match[1] =~ /[a-z_]/ ? BRIGHT_MAGENTA : BRIGHT_RED
        "#{color}#{match}#{RESET}"
      end
      return color_shell_input(text) if @shell_mode

      shell_hint = inline_shell_hint(text)
      return "#{decorated}#{shell_hint}" if shell_hint
      return decorated if text.lstrip.start_with?("!") || text.lstrip.start_with?("/paste")

      hint = @interpreter.inline_signature_for(text)
      hint ? "#{decorated}#{DIM}  #{hint}#{RESET}" : decorated
    end

    def color_shell_input(text)
      text.to_s.lines("\n").map do |line|
        if line.end_with?("\n")
          "#{YELLOW}#{line.delete_suffix("\n")}#{RESET}\n"
        else
          "#{YELLOW}#{line}#{RESET}"
        end
      end.join
    end

    def inline_shell_hint(text)
      stripped = text.to_s.strip
      return "#{BRIGHT_MAGENTA}  shell command#{RESET}" if stripped == "!"
      return "#{BRIGHT_MAGENTA}  shell command#{RESET}" if stripped.start_with?("!")

      nil
    end

    def print_banner
      puts "#{BOLD}#{YELLOW}✶ Tungsten#{RESET} #{DIM}v#{VERSION}#{RESET}"
      puts "#{DIM}  Ctrl+D to exit · shift+enter to submit blocks#{RESET}"
      puts
    end

    def prompt
      return "#{YELLOW}! #{RESET}" if @shell_mode

      "#{MAGENTA}wit#{RESET}> "
    end

    def continuation_prompt
      "#{DIM}  ·  #{RESET}"
    end

    # ── Main loop ─────────────────────────────────────────────────────

    def repl_loop
      loop do
        print_separator
        print_prompt_footer

        input = read_reline_input
        next if input == :interrupted

        break if input.nil? # Ctrl+D

        erase_separator(input)
        clear_below

        # Strip trailing blank lines used as block terminator
        input = input.sub(/\n{2,}\z/, "")
        if input.strip.empty?
          handle_empty_input
          next
        end

        stripped = input.strip
        # Any non-empty command invalidates a pending plot-scrub; the plot
        # branch below re-arms it.
        @pending_plot_scrub = nil
        Reline::HISTORY << input if remember_history?(stripped)
        if @shell_mode
          handle_shell_mode_input(input)
        elsif stripped == "?"
          print_shortcuts
        elsif stripped == "!"
          enter_shell_mode
        elsif stripped.start_with?("!")
          handle_shell_command(stripped.delete_prefix("!").lstrip)
        elsif stripped == "/paste"
          handle_paste_mode
        elsif stripped.start_with?("#?")
          handle_method_reference_query(stripped.delete_prefix("#?").strip, mode: :doc)
        elsif stripped.start_with?("?")
          arg = stripped.delete_prefix("?").lstrip
          if looks_like_complex?(arg)
            handle_complex_command(arg)
          elsif arg.include?("Σ") || arg.include?("∫") || looks_like_polynomial?(arg)
            handle_plot_command(arg)
          else
            handle_inspection_query(arg)
          end
        elsif stripped.start_with?("/model")
          handle_model_command(stripped.delete_prefix("/model").lstrip)
        elsif stripped.start_with?("@aiku")
          handle_aiku_query(stripped.delete_prefix("@aiku").lstrip)
        elsif stripped.start_with?("@ai")
          handle_ai_query(stripped.delete_prefix("@ai").lstrip)
        elsif stripped.start_with?("@claude")
          handle_claude_query(stripped.delete_prefix("@claude").lstrip)
        else
          evaluate_and_display(input)
        end
      end
    end

    def read_reline_input
      previous_repl = Thread.current[:tungsten_wit_repl]
      Thread.current[:tungsten_wit_repl] = self
      Reline.readmultiline(prompt, false) { |buf| code_complete?(buf) }
    rescue Interrupt
      clear_below
      puts
      :interrupted
    ensure
      Thread.current[:tungsten_wit_repl] = previous_repl
    end

    def activate_shell_mode_from_bang
      return false if @shell_mode

      @shell_mode = true
      @shell_mode_one_shot = true
      @shell_mode_pending_notice = false
      sanitize_history!
      true
    end

    def cancel_shell_mode_from_backspace
      return false unless @shell_mode && @shell_mode_one_shot

      leave_shell_mode(silent: true)
      true
    end

    def remember_history?(stripped)
      return false if stripped == "!"
      return false if @shell_mode

      true
    end

    def persisted_history?(entry)
      entry.to_s.strip != "!"
    end

    def sanitize_history!
      Reline::HISTORY.delete_if { |entry| !persisted_history?(entry) }
    end

    def handle_empty_input
      if @shell_mode && @shell_mode_one_shot
        erase_last_rendered_prompt_line
        leave_shell_mode(silent: true)
        return
      end

      # A blank Enter right after a `? …` plot scrubs that plot.
      if @pending_plot_scrub
        ps = @pending_plot_scrub
        if ps[:kind] == :complex
          ps[:expr], ps[:rot] = scrub_complex(ps[:expr], ps[:rot] || 0)
        else
          ps[:range_src], ps[:poly] = scrub_plot(ps[:range_src], ps[:op], ps[:poly])
        end
        return
      end

      enter_scrub_mode if @session_log.any? && !@shell_mode
    end

    def enter_shell_mode(one_shot: true)
      @shell_mode = true
      @shell_mode_one_shot = one_shot
    end

    def leave_shell_mode(*)
      @shell_mode = false
      @shell_mode_one_shot = false
      @shell_mode_pending_notice = false
      @shell_mode_backspace_cancel = false
    end

    def handle_shell_mode_input(input)
      stripped = input.to_s.strip
      if stripped == "!" || stripped == "exit"
        erase_last_rendered_prompt_line
        leave_shell_mode(silent: true)
        return
      end

      begin
        handle_shell_command(input)
      ensure
        leave_shell_mode if @shell_mode_one_shot
      end
    end

    def erase_last_rendered_prompt_line
      return unless @tty

      print "\e[1A\e[2K\r"
      $stdout.flush
    end

    def handle_shell_command(command)
      command = command.to_s.strip
      return enter_shell_mode if command.empty?

      shell = ENV["SHELL"].to_s
      shell = "/bin/sh" if shell.empty?

      return change_shell_directory(command) if shell_cd_command?(command)

      output, status = Open3.capture2e({ "PWD" => @shell_cwd }, shell, "-lc", command, chdir: @shell_cwd)
      print output unless output.empty?
      puts "#{DIM}  exit #{status.exitstatus}#{RESET}" unless status.success?
    rescue StandardError => e
      puts "#{BRIGHT_RED}shell error: #{e.message}#{RESET}"
    end

    def shell_cd_command?(command)
      words = Shellwords.split(command)
      words.first == "cd" && words.length <= 2
    rescue ArgumentError
      false
    end

    def change_shell_directory(command)
      words = Shellwords.split(command)
      target = words[1]
      target = Dir.home if target.nil? || target.empty?
      target = @previous_shell_cwd if target == "-" && @previous_shell_cwd
      expanded = File.expand_path(target, @shell_cwd)
      raise Errno::ENOENT, target unless Dir.directory?(expanded)

      @previous_shell_cwd = @shell_cwd
      @shell_cwd = expanded
      puts "#{DIM}  cwd #{expanded}#{RESET}"
    end

    def handle_paste_mode(io: $stdin)
      puts "#{DIM}paste mode · finish with /end on its own line#{RESET}"
      source = read_paste_source(io)
      if source.strip.empty?
        puts "#{DIM}  empty paste#{RESET}"
      else
        evaluate_and_display(source)
      end
    end

    def read_paste_source(io)
      lines = []
      while (line = io.gets)
        break if line.chomp == "/end"

        lines << line
      end
      lines.join.sub(/\n\z/, "")
    end

    # ── Completeness detection ────────────────────────────────────────

    # Called by Reline on each Enter press. Returns true when the buffer
    # is a complete expression ready to evaluate.
    def code_complete?(buffer)
      stripped_buffer = buffer.to_s.strip
      return true if @shell_mode || stripped_buffer.start_with?("!") || stripped_buffer == "/paste"
      return true if buffer.strip.empty?

      lines = buffer.split("\n", -1)

      # Two consecutive blank lines → force submit (block terminator).
      # Reline's callback always appends "\n", so split produces a trailing "".
      # Three consecutive empties from split = two user-entered blank lines.
      if lines.size >= 4 && lines[-1].strip.empty? && lines[-2].strip.empty? && lines[-3].strip.empty?
        return true
      end

      # Unmatched brackets/parens
      return false if buffer.count("([{") > buffer.count(")]}")

      last_nonblank = lines.reject { |l| l.strip.empty? }.last
      return true unless last_nonblank

      stripped = last_nonblank.strip

      # Block-opening keyword at start of last meaningful line → need indented body
      return false if BLOCK_OPENERS.any? { |kw| stripped.match?(/\A#{kw}\b/) }

      # -> (function def) or + ClassName (class def) open blocks
      # Also catch -> at end of line (block passed to method: .each ->)
      return false if stripped.match?(/\A->/) || stripped.match?(/\A\+ [A-Z]/)
      return false if stripped.match?(/->\s*\z/) || stripped.match?(/->\([^)]*\)\s*\z/)

      # Last meaningful line is indented → still inside a block body
      return false if last_nonblank.start_with?("  ") || last_nonblank.start_with?("\t")

      true
    end

    # ── Auto-indent ───────────────────────────────────────────────────

    # Called by Reline to determine indentation.
    #   is_newline=true  → user just pressed Enter; return indent for the new line
    #   is_newline=false → user is typing; re-indent current line if it's a dedenter
    def calc_indent(lines, line_index, _byte_pointer, is_newline)
      if is_newline
        # Look backwards past blank lines to find the effective previous line
        prev_line = nil
        (line_index - 1).downto(0) do |i|
          unless lines[i].strip.empty?
            prev_line = lines[i]
            break
          end
        end
        return 0 unless prev_line

        prev_indent = prev_line[/\A */].size
        prev_stripped = prev_line.strip

        if opens_block?(prev_stripped)
          prev_indent + 2
        else
          prev_indent
        end
      else
        current_line = lines[line_index]
        return nil unless current_line

        current_indent = current_line[/\A */].size
        current_stripped = current_line.strip

        if DEDENT_KEYWORDS.any? { |kw| current_stripped.match?(/\A#{kw}\b/) }
          [current_indent - 2, 0].max
        else
          # Return current indent to prevent Reline from resetting it
          current_indent
        end
      end
    end

    def opens_block?(stripped)
      BLOCK_OPENERS.any? { |kw| stripped.match?(/\A#{kw}\b/) } ||
        stripped.match?(/\A->/) ||
        stripped.match?(/\A\+ [A-Z]/) ||
        stripped.match?(/->\s*\z/) ||
        stripped.match?(/->\([^)]*\)\s*\z/)
    end

    # ── Evaluation ────────────────────────────────────────────────────

    def evaluate_and_display(input)
      result = nil
      output = StringIO.new
      error = nil

      old_stdout = $stdout
      spinner = start_spinner

      begin
        $stdout = output
        result = @interpreter.run(input)
      rescue Tungsten::Error => e
        error = e
      rescue StandardError => e
        error = e
      ensure
        $stdout = old_stdout
        stop_spinner(spinner)
      end

      captured = output.string
      print captured unless captured.empty?

      if error
        print_error(error)
        log_session(input, captured, "✗ #{error.message}")
      else
        @interpreter.set_variable("_", result)
        print_result(result)
        log_session(input, captured, plain_value(result))
      end
    end

    def handle_inspection_query(query)
      query = query.to_s.strip
      return print_shortcuts if query.empty?

      return handle_method_reference_query(query, mode: :source) if method_reference_query?(query)

      if query.start_with?("u0x")
        puts @interpreter.inspect_wvalue_literal(query)
        return
      end

      result = nil
      output = StringIO.new
      error = nil

      old_stdout = $stdout
      spinner = start_spinner

      begin
        $stdout = output
        result = @interpreter.run(query)
      rescue Tungsten::Error => e
        error = e
      rescue StandardError => e
        error = e
      ensure
        $stdout = old_stdout
        stop_spinner(spinner)
      end

      captured = output.string
      print captured unless captured.empty?

      if error
        print_error(error)
      else
        puts @interpreter.inspect_runtime_value(result)
        log_session(query, captured, plain_value(result), mode: :inspection)
      end
    rescue ArgumentError => e
      print_error(Tungsten::Error.new(e.message))
    end

    PLOT_SUPERSCRIPTS = { "⁰" => "0", "¹" => "1", "²" => "2", "³" => "3", "⁴" => "4",
                          "⁵" => "5", "⁶" => "6", "⁷" => "7", "⁸" => "8", "⁹" => "9" }.freeze

    # `? <range>/Σ(<polynomial>)` — plot the polynomial over the range as a
    # braille chart. This (Ruby) REPL doesn't parse the Σ / superscript /
    # implicit-multiplication surface syntax, so we extract the range bounds
    # (evaluated through the interpreter, so a session variable like `range`
    # resolves) and the polynomial coefficients here, then shell out to the
    # compiled tungsten-drawille bit for the rendering.
    def handle_plot_command(expr)
      m = expr.match(/\A(.+?)\s*\/\s*([Σ∫])\s*\((.*)\)\s*\z/u)
      if m
        range_src = m[1].strip
        op = m[2]
        poly_src = m[3].strip
        # Drop an explicit bound variable: Σ(x -> 2x + 3) → "2x + 3".
        if (bm = poly_src.match(/\A\w+\s*->\s*(.*)\z/m))
          poly_src = bm[1].strip
        end
        lo, hi = resolve_plot_range(range_src)
        if lo.nil? || hi.nil?
          puts "  plot: couldn't resolve range #{range_src.inspect}"
          return
        end
      else
        # Bare polynomial: `? x²⁰ + 17x¹³ - …` — no range given, so auto-range
        # around its real zeroes (the curve through the x-axis is the point).
        range_src = nil
        op = "Σ"
        poly_src = expr.strip
        lo, hi = choose_plot_range(polynomial_coeffs(poly_src))
      end

      if polynomial_coeffs(poly_src).empty?
        puts "  plot: couldn't parse polynomial #{poly_src.inspect}"
        return
      end

      bin = File.join(REPO_ROOT, "bits", "tungsten-drawille", "bin", "drawille")
      unless File.executable?(bin)
        puts "  plot: drawille bit not built — run `bin/tungsten build`"
        return
      end
      coeffs0 = polynomial_coeffs(poly_src)
      out = plot_render_string(lo, hi, coeffs0, op == "∫")
      cl = plot_complex_line(coeffs0)
      out += "#{cl}\n" if cl
      il = plot_integral_line(op, coeffs0)
      out += "\n#{il}\n" if il
      print out
      @plot_render_lines = out.count("\n")
      # Defer scrubbing to an empty Enter (like the eval scrubber), which then
      # mutates this very plot in place.
      @pending_plot_scrub = { range_src: range_src, op: op, poly: poly_src }
    end

    # A bare `? <expr>` is treated as a polynomial to plot (rather than an
    # inspection query) when it's built only of polynomial characters and
    # actually contains an x term.
    def looks_like_polynomial?(s)
      s = s.to_s.strip
      return false unless s.match?(/\A[-+0-9\s.x*^()⁰¹²³⁴⁵⁶⁷⁸⁹]+\z/)
      s.include?("x") && polynomial_coeffs(s).length > 1
    end

    # ── Complex-number Argand viz: `? 3+4i`, `? (1+i)*(2+3i)` ──────────────
    # The imaginary unit `i` is the discriminator: an expression built only of
    # complex characters (digits, + - * /, parens, dot, and `i`) that contains
    # an `i` routes to the Argand plane. Any other letter (so any normal
    # inspection query) fails the charset check and falls through.
    def looks_like_complex?(s)
      s = s.to_s.strip
      return false if s.empty?
      return false unless s.match?(%r{\A[-+0-9.\s*/()i]+\z})
      s.include?("i")
    end

    COMPLEX_SCALE = 1000

    # Split a complex expression into multiplicative factors (each a complex
    # literal a±bi, optionally parenthesised) and the operators between them.
    # No arithmetic happens here — the complex math is all done in Tungsten by
    # the bit. Returns [factors, ops] with factors = [[re, im], …] (floats) and
    # ops = ["*"/"/", …]; nil on a parse miss.
    def tokenize_complex(expr)
      s = expr.to_s.gsub(/\s+/, "")
      return nil if s.empty?
      pieces = []
      ops = []
      depth = 0
      buf = +""
      s.each_char do |ch|
        if ch == "("
          depth += 1
          buf << ch
        elsif ch == ")"
          depth -= 1
          buf << ch
        elsif depth.zero? && (ch == "*" || ch == "/")
          pieces << buf
          ops << ch
          buf = +""
        else
          buf << ch
        end
      end
      pieces << buf
      return nil if pieces.any?(&:empty?)
      factors = pieces.map { |p| parse_complex_literal(p) }
      return nil if factors.any?(&:nil?)
      [factors, ops]
    end

    # Parse one complex literal "a±bi" (or "(a±bi)") to [re, im] floats.
    def parse_complex_literal(str)
      s = str.gsub(/\s+/, "")
      s = s[1..-2] if s.start_with?("(") && s.end_with?(")")
      return nil if s.empty?
      return nil unless s.match?(%r{\A[-+0-9.i]+\z})
      re = 0.0
      im = 0.0
      s.scan(/[+-]?[^+-]+/).each do |term|
        next if term.empty?
        if term.end_with?("i")
          c = term[0..-2]
          c = "1" if c.empty? || c == "+"
          c = "-1" if c == "-"
          im += c.to_f
        else
          re += term.to_f
        end
      end
      [re, im]
    end

    def complex_plot_rows
      plot_terminal_rows
    end

    # Shell the integer-scaled operands to the drawille bit's --argand mode;
    # returns its stdout (the braille plane plus `@@ role re im abs arg` records,
    # all computed in Tungsten Complex<f64>).
    def render_complex_string(factors, ops, rot = 0)
      bin = File.join(REPO_ROOT, "bits", "tungsten-drawille", "bin", "drawille")
      return "" unless File.executable?(bin)
      comps = factors.map { |re, im| [(re * COMPLEX_SCALE).round, (im * COMPLEX_SCALE).round] }
      args = ["--argand", "--scale", COMPLEX_SCALE.to_s, "--rows", complex_plot_rows.to_s]
      args += ["--rotate", rot.to_s] unless rot.zero?
      args += [comps[0][0].to_s, comps[0][1].to_s]
      ops.each_with_index { |op, k| args += [op, comps[k + 1][0].to_s, comps[k + 1][1].to_s] }
      # stdin from /dev/null so the child can't steal scrub keystrokes; stderr
      # silenced so an unsupported op's abort (see handle_complex_command) shows
      # a clean note instead of a runtime backtrace.
      IO.popen([bin, *args, { in: File::NULL, err: File::NULL }], &:read).to_s
    end

    # Split the bit output into [plane_string, records]; each record is
    # {role:, re:, im:, abs:, arg:} parsed from a `@@ …` line (arg in radians).
    def split_complex_output(out)
      plane = []
      records = []
      out.each_line do |line|
        if line.start_with?("@@ ")
          _, role, re, im, ab, ar = line.split
          records << { role: role, re: re.to_f, im: im.to_f, abs: ab.to_f, arg: ar.to_f }
        else
          plane << line
        end
      end
      [plane.join, records]
    end

    def fmt_num_plain(x)
      r = x.round(3)
      r == r.to_i ? r.to_i.to_s : r.to_s
    end

    # Render [re, im] as a complex literal: "3+4i", "-1+5i", "0.8+0.6i",
    # "3" (real only), "4i" / "-i" (imaginary only).
    def fmt_complex(re, im)
      rs = fmt_num_plain(re)
      return rs if im.abs < 1e-9
      icoeff = (im.abs - 1.0).abs < 1e-9 ? "" : fmt_num_plain(im.abs)
      if re.abs < 1e-9
        "#{im.negative? ? "-" : ""}#{icoeff}i"
      else
        "#{rs}#{im.negative? ? "-" : "+"}#{icoeff}i"
      end
    end

    def deg(rad)
      d = (rad * 180.0 / Math::PI).round(2)
      d == d.to_i ? d.to_i.to_s : d.to_s
    end

    # The annotation block beneath the plane: the result's z / |z| / arg, plus
    # one "rotate/scale" read-out per multiplier — the multiply-as-rotation
    # story. Every number originates in the bit's Tungsten computation.
    def complex_annotation(ops, records)
      return "" if records.empty?
      result = records.find { |r| r[:role] == "result" } || records.first
      # `arg` leads so the rotation knob stays put while scrubbing — z's text
      # width changes as it rotates, which would otherwise shift a trailing arg.
      lines = ["  #{DIM}arg = #{deg(result[:arg])}°   z = #{fmt_complex(result[:re], result[:im])}   " \
               "|z| = #{fmt_num_plain(result[:abs])}#{RESET}"]
      operands = records.select { |r| r[:role] == "operand" }
      ops.each_with_index do |op, k|
        nxt = operands[k + 1]
        next unless nxt
        sym = op == "*" ? "×" : "÷"
        rsign = nxt[:arg].negative? ? "" : "+"
        lines << "  #{DIM}#{sym} (#{fmt_complex(nxt[:re], nxt[:im])}): " \
                 "rotate #{rsign}#{deg(nxt[:arg])}°, scale ×#{fmt_num_plain(nxt[:abs])}#{RESET}"
      end
      lines.join("\n") + "\n"
    end

    # `? <complex>` — draw the Argand plane and the |z|/arg annotations, then
    # arm a blank-Enter scrub (mirroring the polynomial plot flow).
    def handle_complex_command(expr)
      parsed = tokenize_complex(expr)
      if parsed.nil?
        puts "  complex: couldn't parse #{expr.inspect}"
        return
      end
      bin = File.join(REPO_ROOT, "bits", "tungsten-drawille", "bin", "drawille")
      unless File.executable?(bin)
        puts "  plot: drawille bit not built — run `bin/tungsten build`"
        return
      end
      factors, ops = parsed
      plane, records = split_complex_output(render_complex_string(factors, ops))
      # No records ⇒ the bit aborted before emitting (it prints the plane and
      # the @@ records together) — almost always a drawille bit built without
      # generics. Degrade with a clear note rather than a torn/blank plane.
      if records.empty?
        puts "  complex: couldn't render — rebuild the drawille bit (`bin/tungsten build`)"
        return
      end
      ann = complex_annotation(ops, records)
      print plane
      print ann
      @plot_render_lines = plane.count("\n") + ann.count("\n")
      @pending_plot_scrub = { kind: :complex, expr: expr, rot: 0 }
    end

    # Re-enter the complex scrub on the field last left — the angle knob or a
    # component digit — so repeated blank-Enter scrubs resume where you were
    # (`@complex_scrub_field` is :angle, a digit index, or nil). Defaults to the
    # last component the first time. `num_digits` is the current component count
    # (the angle knob is appended after them, at index num_digits).
    def complex_resume_cursor(num_digits)
      f = @complex_scrub_field
      return [num_digits - 1, 0].max if f.nil?
      return num_digits if f == :angle
      f.clamp(0, [num_digits - 1, 0].max)
    end

    # Every scrubbable number (real/imaginary component) in the expression.
    def complex_scrub_targets(expr)
      ts = []
      expr.scan(/\d+/) do
        m = Regexp.last_match
        ts << { start: m.begin(0), len: m[0].length }
      end
      ts
    end

    # Interactive scrub of a complex expression. ←→ selects a component digit
    # OR the rotation knob (appended last); ↑↓ nudges (±1), }{ nudges (±10).
    # Component nudges cross zero (flip the term's sign). The rotation knob is
    # the `arg = …°` read-out: nudging it multiplies the input by e^(iθ) in the
    # bit (multiply-as-rotation, |z| preserved). Returns [expr, rot]. The cursor
    # defaults to the last component so plain ↑↓ still scrubs values; → reaches
    # the angle knob. Static off a tty.
    def scrub_complex(expr, rot = 0)
      digits = complex_scrub_targets(expr)
      targets = digits + [{ angle: true }]
      unless $stdout.tty?
        factors, ops = tokenize_complex(expr)
        plane, records = split_complex_output(render_complex_string(factors, ops, rot))
        print plane
        print complex_annotation(ops, records)
        return [expr, rot]
      end
      cursor = complex_resume_cursor(digits.length)
      @scrub_lines_drawn = @plot_render_lines ? @plot_render_lines + 3 : 0
      print "\e[?25l" # hide the cursor during the in-place redraws
      begin
      redraw_complex_scrub(expr, targets, cursor, rot)
      IO.console.raw do |io|
        loop do
          c = io.getc
          break if c.nil?
          step = 0
          case c
          when "\e"
            seq = io.read_nonblock(2) rescue ""
            case seq
            when "[D" then cursor = (cursor - 1) % targets.length
            when "[C" then cursor = (cursor + 1) % targets.length
            when "[A" then step = 1
            when "[B" then step = -1
            else break
            end
          # On the rotation knob, [ ] snap by ±15° (protractor steps); on a
          # component digit they keep the ±1 of +/k and _/j.
          when "]" then step = (targets[cursor] && targets[cursor][:angle]) ? 15 : 1
          when "[" then step = (targets[cursor] && targets[cursor][:angle]) ? -15 : -1
          when "+", "k" then step = 1
          when "_", "j" then step = -1
          when "}" then step = 10
          when "{" then step = -10
          when "h" then cursor = (cursor - 1) % targets.length
          when "l" then cursor = (cursor + 1) % targets.length
          when "\r", "\n", "q", "\x03", "\x04" then break
          else next
          end
          if step != 0
            if targets[cursor][:angle]
              rot += step
            else
              t = targets[cursor]
              expr = scrub_coeff(expr, t[:start], t[:len], step)
              digits = complex_scrub_targets(expr)
              targets = digits + [{ angle: true }]
              cursor = cursor.clamp(0, targets.length - 1)
            end
          end
          redraw_complex_scrub(expr, targets, cursor, rot)
        end
      end
      ensure
        print "\e[?25h" # restore the cursor — always, even if a redraw raises
      end
      # Remember the field for the next scrub: :angle for the knob, else the
      # component index.
      @complex_scrub_field = targets[cursor]&.dig(:angle) ? :angle : cursor
      print "\r\n"
      @plot_render_lines = @scrub_lines_drawn
      [expr, rot]
    end

    def redraw_complex_scrub(expr, targets, cursor, rot = 0)
      @scrub_lines_drawn ||= 0
      t = targets[cursor]
      angle_sel = t && t[:angle]
      hl = ->(s, st, ln) { s[0...st] + "\e[7m" + s[st, ln] + "\e[0m" + s[(st + ln)..] }
      shown = (t && !angle_sel) ? hl.call(expr, t[:start], t[:len]) : expr
      factors, ops = tokenize_complex(expr)
      plane, records = split_complex_output(render_complex_string(factors, ops, rot))
      ann = complex_annotation(ops, records)
      # When the rotation knob is selected, reverse-video the arg value (the
      # number only — leave the ° dim) so the knob reads as "what you're turning".
      if angle_sel
        ann = ann.sub(/(arg = )([^\e°]*?)(°)/) do
          "#{Regexp.last_match(1)}\e[7m#{Regexp.last_match(2)}\e[0m\e[2m#{Regexp.last_match(3)}"
        end
      end
      if @scrub_lines_drawn > 1
        (@scrub_lines_drawn - 1).times { print "\e[A" }
      end
      print "\r\e[J"
      lines = 1
      knob = angle_sel ? "   #{DIM}↻ #{rot >= 0 ? "+" : ""}#{rot}°#{RESET}" : ""
      hint = angle_sel ? "↑↓ ±1° · [ ] ±15° · ←→ select · q quit" : "↑↓ value · ←→ select · q quit"
      print "#{DIM}scrub>#{RESET} ? #{shown}#{knob}   #{DIM}#{hint}#{RESET}"
      plane.split("\n").each do |line|
        print "\r\n#{line}"
        lines += 1
      end
      ann.split("\n").each do |line|
        print "\r\n#{line}"
        lines += 1
      end
      @scrub_lines_drawn = lines
      $stdout.flush
    end

    def plot_eval_f(coeffs, x)
      coeffs.each_index.sum { |k| coeffs[k] * (x**k) }
    end

    # Approximate the real zeroes by scanning for sign changes within the Cauchy
    # bound on |root| (1 + max|cₖ|/|c_lead|).
    def polynomial_roots(coeffs)
      deg = coeffs.length - 1
      return [] if deg < 1
      lead = coeffs[deg].to_f
      return [] if lead.zero?
      bound = 1.0 + (coeffs[0...deg].map(&:abs).max.to_f / lead.abs)
      bound = bound.clamp(1.0, 1000.0)
      roots = []
      steps = 4000
      prev_x = -bound
      prev_y = plot_eval_f(coeffs, prev_x)
      (1..steps).each do |i|
        x = -bound + (2.0 * bound * i / steps)
        y = plot_eval_f(coeffs, x)
        # Catch a sign transition, including a root that lands exactly on a grid
        # sample (y == 0) — common for integer roots — without double-counting.
        if (prev_y < 0 && y >= 0) || (prev_y > 0 && y <= 0)
          roots << ((prev_x + x) / 2.0)
        end
        prev_x = x
        prev_y = y
      end
      roots
    end

    # Choose an integer range that brackets one or two zeroes (the ones nearest
    # 0), with a unit of padding. Falls back to a symmetric window.
    def choose_plot_range(coeffs)
      roots = polynomial_roots(coeffs)
      return [-10, 10] if roots.empty?
      sel = roots.sort_by(&:abs).first(2).sort
      lo = sel.first.floor - 1
      hi = sel.last.ceil + 1
      hi = lo + 1 if hi <= lo
      [lo, hi]
    end

    # The antiderivative ∫P dx = Σ cₖ/(k+1)·x^(k+1) + C, formatted with reduced
    # fractional coefficients and superscript powers.
    def integral_formula(coeffs)
      terms = []
      coeffs.each_index do |k|
        c = coeffs[k]
        next if c.zero?
        den = k + 1
        g = c.abs.gcd(den)
        terms << [c / g, den / g, k + 1]
      end
      return "C" if terms.empty?
      s = +""
      terms.reverse.each_with_index do |(num, den, exp), i|
        mag = num.abs
        coeff = den == 1 ? mag.to_s : "#{mag}/#{den}"
        xp = exp == 1 ? "x" : "x#{plot_to_super(exp)}"
        coeff = "" if coeff == "1"   # 1·xⁿ → xⁿ
        body = coeff + xp
        s << (i.zero? ? (num.negative? ? "-#{body}" : body) : (num.negative? ? " - #{body}" : " + #{body}"))
      end
      s << " + C"
      s
    end

    def plot_integral_line(op, coeffs)
      return nil unless op == "∫"
      "  #{DIM}∫ = #{integral_formula(coeffs)}#{RESET}"
    end

    # All n roots (real and complex) via Durand–Kerner iteration on the monic
    # polynomial. Ruby's Complex makes this a few lines.
    def polynomial_all_roots(coeffs)
      c = coeffs.dup
      c.pop while c.length > 1 && c.last.zero?
      deg = c.length - 1
      return [] if deg < 1
      lead = c[deg].to_f
      return [] if lead.zero?
      mon = (0..deg).map { |k| c[deg - k] / lead } # descending, monic (mon[0]=1)
      evalp = ->(z) { mon.reduce(Complex(0.0)) { |a, m| a * z + m } }
      roots = (0...deg).map { |k| Complex(0.4, 0.9)**k }
      80.times do
        moved = 0.0
        roots = roots.each_index.map do |i|
          den = Complex(1.0)
          roots.each_index { |j| den *= (roots[i] - roots[j]) if j != i }
          next roots[i] if den.abs.zero?
          delta = evalp.call(roots[i]) / den
          moved += delta.abs
          roots[i] - delta
        end
        break if moved < 1e-12
      end
      roots
    end

    def plot_fmt_num(x)
      r = x.round(2)
      r == r.to_i ? r.to_i.to_s : r.to_s
    end

    # The complex (non-real) zeroes, formatted a ± bi, conjugate pairs included.
    def plot_complex_line(coeffs)
      cx = polynomial_all_roots(coeffs).select { |z| z.imaginary.abs > 1e-4 }
      return nil if cx.empty?
      parts = cx.sort_by { |z| [z.real, z.imaginary] }.map do |z|
        sign = z.imaginary.negative? ? "−" : "+"
        "#{plot_fmt_num(z.real)} #{sign} #{plot_fmt_num(z.imaginary.abs)}i"
      end
      "  #{DIM}complex zeroes: #{parts.join(",  ")}#{RESET}"
    end

    PLOT_SUPER_DIGITS = %w[⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹].freeze

    def plot_to_super(n)
      n.to_s.chars.map { |c| c =~ /\d/ ? PLOT_SUPER_DIGITS[c.to_i] : c }.join
    end

    def plot_super_to_i(s)
      s.chars.map { |c| PLOT_SUPERSCRIPTS[c] || c }.join.to_i
    end

    # Every scrubbable number in the polynomial — coefficients (plain digits)
    # and exponents (plain or superscript). A superscript span re-serializes in
    # superscript so a scrubbed exponent stays a superscript.
    PLOT_RANGE_LITERAL = /\A\(?\s*-?\d+\s*\.\.\.?\s*-?\d+\s*\)?\z/

    # All scrubbable numbers across the (literal) range and the polynomial, in
    # left-to-right display order. field :range/:poly; kind :endpoint/:coeff/:exp.
    def plot_scrub_targets(range_src, range_literal, poly_src)
      ts = []
      if range_literal
        range_src.scan(/-?\d+/) do
          m = Regexp.last_match
          ts << { field: :range, start: m.begin(0), len: m[0].length, kind: :endpoint }
        end
      end
      poly_src.scan(/[0-9]+|[⁰¹²³⁴⁵⁶⁷⁸⁹]+/) do
        m = Regexp.last_match
        sup = !(m[0][0] =~ /[⁰¹²³⁴⁵⁶⁷⁸⁹]/).nil?
        before = m.begin(0).positive? ? poly_src[m.begin(0) - 1] : ""
        is_exp = sup || before == "x" || before == "^" || before == "*"
        ts << { field: :poly, start: m.begin(0), len: m[0].length, kind: is_exp ? :exp : :coeff, sup: sup }
      end
      ts
    end

    # Apply a scrub to the target. Returns [range_src, poly_src].
    def plot_scrub_mutate(range_src, poly_src, t, delta)
      if t[:field] == :range
        [scrub_signed_int(range_src, t[:start], t[:len], delta), poly_src]
      elsif t[:kind] == :exp
        text = poly_src[t[:start], t[:len]]
        val = [(t[:sup] ? plot_super_to_i(text) : text.to_i) + delta, 0].max
        rep = t[:sup] ? plot_to_super(val) : val.to_s
        [range_src, poly_src[0...t[:start]] + rep + poly_src[(t[:start] + t[:len])..]]
      else
        [range_src, scrub_coeff(poly_src, t[:start], t[:len], delta)]
      end
    end

    # A signed integer literal — the regex already captured any leading '-'.
    def scrub_signed_int(str, start, len, delta)
      v = str[start, len].to_i + delta
      str[0...start] + v.to_s + str[(start + len)..]
    end

    # A polynomial coefficient: flip the term's +/- operator (or its leading
    # sign) as the value crosses zero, so a coefficient can scrub negative.
    def scrub_coeff(poly, start, len, delta)
      i = start - 1
      i -= 1 while i >= 0 && poly[i] == " "
      if i >= 0 && (poly[i] == "+" || poly[i] == "-")
        j = i - 1
        j -= 1 while j >= 0 && poly[j] == " "
        sign = poly[i] == "-" ? -1 : 1
        nv = sign * poly[start, len].to_i + delta
        if j >= 0   # binary operator (a term precedes it)
          s = poly.dup
          s[i] = nv.negative? ? "-" : "+"
          s[start, len] = nv.abs.to_s
          s
        else        # leading sign: drop it when ≥0, keep '-' when <0
          poly[0...i] + (nv.negative? ? "-" : "") + nv.abs.to_s + poly[(start + len)..]
        end
      else
        nv = poly[start, len].to_i + delta
        poly[0...start] + (nv.negative? ? "-" : "") + nv.abs.to_s + poly[(start + len)..]
      end
    end

    # Plot rows that keep the whole scrub render within the terminal, so the
    # in-line redraw never has to overwrite across a scroll. Budget ~11 lines
    # for the scrub header, axis, labels, zeroes (2), complex line, integral,
    # and a little slack.
    def plot_terminal_rows
      [[terminal_size[0] - 11, 6].max, 15].min
    rescue StandardError
      15
    end

    # Render the plot for the current polynomial by shelling to the bit.
    def plot_render_string(lo, hi, coeffs, fill)
      bin = File.join(REPO_ROOT, "bits", "tungsten-drawille", "bin", "drawille")
      return "" unless File.executable?(bin)
      flags = fill ? ["--auc"] : []
      flags += ["--margin", "1", "--rows", plot_terminal_rows.to_s]
      # Mark the real zeroes within the range — found precisely here and passed
      # as x·10 so the bit just places and labels them.
      zeros = polynomial_roots(coeffs).select { |r| r >= lo && r <= hi }.map { |r| (r * 10).round }
      flags += ["--zeros", zeros.join(",")] unless zeros.empty?
      # Redirect the child's stdin from /dev/null so it can't share (and steal
      # keystrokes from) the console the scrub loop is reading in raw mode.
      IO.popen([bin, *flags, *[lo, hi, *coeffs].map(&:to_s)], in: File::NULL, &:read).to_s
    end

    # lo/hi for the current range: bare → from the polynomial's roots; otherwise
    # resolve the (possibly just-scrubbed) range source.
    def plot_resolve_range(range_src, coeffs)
      return choose_plot_range(coeffs) if range_src.nil?
      resolve_plot_range(range_src)
    end

    # Interactive scrub: ←→ select a number (range endpoint, coefficient, or
    # exponent), ↑↓ nudge it — coefficients and endpoints cross zero — and the
    # plot re-renders live. Returns [range_src, poly_src]. Static off a tty.
    def scrub_plot(range_src, op, poly_src)
      literal = !range_src.nil? && range_src.match?(PLOT_RANGE_LITERAL)
      targets = plot_scrub_targets(range_src, literal, poly_src)
      if targets.empty? || !$stdout.tty?
        coeffs = polynomial_coeffs(poly_src)
        lo, hi = plot_resolve_range(range_src, coeffs)
        print plot_render_string(lo, hi, coeffs, op == "∫")
        il = plot_integral_line(op, coeffs)
        puts il if il
        return [range_src, poly_src]
      end
      # Resume on the field last left (range endpoint / coefficient / exponent),
      # so repeated blank-Enter scrubs land where you were; default to the last.
      cursor = @plot_scrub_field ? @plot_scrub_field.clamp(0, targets.length - 1) : targets.length - 1
      # In-line: the first redraw lands on the plot the previous `? …` command
      # printed (and the empty-Enter prompt below it), overwriting both, so the
      # scrub modifies that plot in place with nothing left behind. The plot is
      # sized to fit the terminal (see plot_rows_for_terminal) so the redraw
      # never has to overwrite across a scroll.
      @scrub_lines_drawn = @plot_render_lines ? @plot_render_lines + 3 : 0
      print "\e[?25l" # hide the cursor during the in-place redraws
      begin
      redraw_plot_scrub(range_src, literal, op, poly_src, targets, cursor)
      IO.console.raw do |io|
        loop do
          c = io.getc
          break if c.nil?
          step = 0
          case c
          when "\e"
            seq = io.read_nonblock(2) rescue ""
            case seq
            when "[D" then cursor = (cursor - 1) % targets.length
            when "[C" then cursor = (cursor + 1) % targets.length
            when "[A" then step = 1
            when "[B" then step = -1
            else break  # lone Esc → exit
            end
          when "]", "+", "k" then step = 1
          when "[", "_", "j" then step = -1
          when "}" then step = 10
          when "{" then step = -10
          when "h" then cursor = (cursor - 1) % targets.length
          when "l" then cursor = (cursor + 1) % targets.length
          when "\r", "\n", "q", "\x03", "\x04" then break
          else next
          end
          if step != 0
            range_src, poly_src = plot_scrub_mutate(range_src, poly_src, targets[cursor], step)
            targets = plot_scrub_targets(range_src, literal, poly_src)
            cursor = cursor.clamp(0, targets.length - 1)
          end
          redraw_plot_scrub(range_src, literal, op, poly_src, targets, cursor)
        end
      end
      ensure
        print "\e[?25h" # restore the cursor — always, even if a redraw raises
      end
      @plot_scrub_field = cursor   # resume here on the next blank-Enter scrub
      print "\r\n"
      # The scrub's final render is now the plot on screen (taller than the
      # original `? …` plot once zeroes/complex lines appeared). Record its size
      # so a *repeat* blank-Enter scrub lands its first redraw on this render
      # instead of overshooting and leaving a `scrub>` header behind each time.
      @plot_render_lines = @scrub_lines_drawn
      [range_src, poly_src]
    end

    def redraw_plot_scrub(range_src, literal, op, poly_src, targets, cursor)
      @scrub_lines_drawn ||= 0
      t = targets[cursor]
      hl = ->(s, st, ln) { s[0...st] + "\e[7m" + s[st, ln] + "\e[0m" + s[(st + ln)..] }
      rng = (range_src && t[:field] == :range) ? hl.call(range_src, t[:start], t[:len]) : range_src
      pol = (t[:field] == :poly) ? hl.call(poly_src, t[:start], t[:len]) : poly_src
      query = range_src ? "? #{rng}/#{op}(#{pol})" : "? #{pol}"
      coeffs = polynomial_coeffs(poly_src)
      lo, hi = plot_resolve_range(range_src, coeffs)
      plot_lines = plot_render_string(lo, hi, coeffs, op == "∫").split("\n")

      if @scrub_lines_drawn > 1
        (@scrub_lines_drawn - 1).times { print "\e[A" }
      end
      print "\r\e[J"
      lines = 1
      print "#{DIM}scrub>#{RESET} #{query}   #{DIM}↑↓ value · ←→ select · q quit#{RESET}"
      plot_lines.each do |line|
        print "\r\n#{line}"
        lines += 1
      end
      cl = plot_complex_line(coeffs)
      if cl
        print "\r\n#{cl}"
        lines += 1
      end
      il = plot_integral_line(op, coeffs)
      if il
        print "\r\n\r\n#{il}"
        lines += 2
      end
      @scrub_lines_drawn = lines
      $stdout.flush
    end

    # Resolve the range bounds — try the interpreter first (so `range` and any
    # expression yielding a Range work), then fall back to a literal a..b / a...b.
    def resolve_plot_range(src)
      lo = plot_eval_int("(#{src}).first")
      hi = plot_eval_int("(#{src}).last")
      if (lo.nil? || hi.nil?) && (rm = src.match(/\(?\s*(-?\d+)\s*\.\.(\.?)\s*(-?\d+)\s*\)?/))
        lo = rm[1].to_i
        hi = rm[3].to_i
        hi -= 1 unless rm[2].empty?
      end
      [lo, hi]
    end

    def plot_eval_int(src)
      Integer(@interpreter.run(src).to_s)
    rescue StandardError
      nil
    end

    # Parse "92x⁷ + 13x³ - 5x + 8" into a dense coefficient list [c0, c1, …]
    # where ck is the coefficient of x^k. Handles implicit multiplication
    # (2x = 2·x), superscript or **/^ powers, signs, and bare constants.
    def polynomial_coeffs(src)
      s = src.gsub(/\s+/, "").gsub(/[⁰¹²³⁴⁵⁶⁷⁸⁹]/) { |c| PLOT_SUPERSCRIPTS[c] }
      coeffs = []
      s.scan(/[+-]?[^+-]+/).each do |raw|
        term = raw
        next if term.empty?
        sign = 1
        if term.start_with?("-")
          sign = -1
          term = term[1..]
        elsif term.start_with?("+")
          term = term[1..]
        end
        if term.include?("x")
          before, after = term.split("x", 2)
          coeff = before.empty? ? 1 : before.to_i
          after = after.sub(/\A(\*\*|\^)/, "")
          power = after.empty? ? 1 : after.to_i
        else
          coeff = term.to_i
          power = 0
        end
        coeffs[power] = (coeffs[power] || 0) + (sign * coeff)
      end
      (0...coeffs.length).map { |i| coeffs[i] || 0 }
    end

    def method_reference_query?(query)
      query.match?(/\A([A-Z][\w:]*|\w+)#([^\s]+)\z/)
    end

    def handle_method_reference_query(query, mode:)
      ref = @interpreter.method_reference(query)
      unless ref
        print_error(Tungsten::Error.new("unknown method reference '#{query}'"))
        return
      end

      puts "  method   #{ref[:ref]}"
      puts "  sig      #{ref[:signature]}"
      puts "  kind     #{ref[:kind]}"
      puts "  location #{ref[:location]}"
      if mode == :doc
        puts "  doc      #{ref[:doc]}"
      else
        puts "  source"
        ref[:source].each { |line| puts "           #{line}" }
      end
    end

    def log_session(input, captured, result_summary, mode: :evaluation)
      parts = []
      parts << captured.strip unless captured.strip.empty?
      parts << result_summary
      @session_log << { input: input.strip, result: parts.join("\n  "), mode: mode }
    end

    # ── Scrub mode (Bret Victor-style token scrubber) ────────────────

    SCRUBABLE = %i[INT FLOAT DECIMAL RATIONAL COLOR CHAR CURRENCY QUANTITY DURATION DATE DATETIME TIME MONTH].freeze

    def enter_scrub_mode
      entry = latest_scrub_entry
      return unless entry

      source = entry[:input]
      tokens = tokenize_for_scrub(source)
      scrub_indices = tokens.each_index.select { |i| SCRUBABLE.include?(tokens[i].type) }
      return if scrub_indices.empty?

      scrub_mode = entry.fetch(:mode, :evaluation)
      cursor = scrub_indices.length - 1  # start at rightmost scrubable token
      @scrub_lines_drawn = 0
      redraw_scrub(source, tokens, scrub_indices, cursor, mode: scrub_mode)

      IO.console.raw do |io|
        loop do
          c = io.getc
          case c
          when "\e"
            seq = io.read_nonblock(2) rescue ""
            case seq
            when "[D"  # left arrow
              cursor = (cursor - 1) % scrub_indices.length
              redraw_scrub(source, tokens, scrub_indices, cursor, mode: scrub_mode)
            when "[C"  # right arrow
              cursor = (cursor + 1) % scrub_indices.length
              redraw_scrub(source, tokens, scrub_indices, cursor, mode: scrub_mode)
            when "[A"  # up arrow — increment
              source, tokens = scrub_mutate(source, tokens, scrub_indices[cursor], 1)
              scrub_indices = tokens.each_index.select { |i| SCRUBABLE.include?(tokens[i].type) }
              cursor = cursor.clamp(0, scrub_indices.length - 1)
              redraw_scrub(source, tokens, scrub_indices, cursor, mode: scrub_mode)
            when "[B"  # down arrow — decrement
              source, tokens = scrub_mutate(source, tokens, scrub_indices[cursor], -1)
              scrub_indices = tokens.each_index.select { |i| SCRUBABLE.include?(tokens[i].type) }
              cursor = cursor.clamp(0, scrub_indices.length - 1)
              redraw_scrub(source, tokens, scrub_indices, cursor, mode: scrub_mode)
            else
              break  # unknown escape → exit
            end
          when "="  # = key — increment (day for dates, +1 for numbers)
            source, tokens = scrub_mutate(source, tokens, scrub_indices[cursor], 1, :small)
            scrub_indices = tokens.each_index.select { |i| SCRUBABLE.include?(tokens[i].type) }
            cursor = cursor.clamp(0, scrub_indices.length - 1)
            redraw_scrub(source, tokens, scrub_indices, cursor, mode: scrub_mode)
          when "-"  # - key — decrement (day for dates, -1 for numbers)
            source, tokens = scrub_mutate(source, tokens, scrub_indices[cursor], -1, :small)
            scrub_indices = tokens.each_index.select { |i| SCRUBABLE.include?(tokens[i].type) }
            cursor = cursor.clamp(0, scrub_indices.length - 1)
            redraw_scrub(source, tokens, scrub_indices, cursor, mode: scrub_mode)
          when "+"  # Shift+= — medium (month for dates, +10 for numbers)
            source, tokens = scrub_mutate(source, tokens, scrub_indices[cursor], 1, :medium)
            scrub_indices = tokens.each_index.select { |i| SCRUBABLE.include?(tokens[i].type) }
            cursor = cursor.clamp(0, scrub_indices.length - 1)
            redraw_scrub(source, tokens, scrub_indices, cursor, mode: scrub_mode)
          when "_"  # Shift+- — medium (month for dates, -10 for numbers)
            source, tokens = scrub_mutate(source, tokens, scrub_indices[cursor], -1, :medium)
            scrub_indices = tokens.each_index.select { |i| SCRUBABLE.include?(tokens[i].type) }
            cursor = cursor.clamp(0, scrub_indices.length - 1)
            redraw_scrub(source, tokens, scrub_indices, cursor, mode: scrub_mode)
          when "]", "}"  # ] — large (year for dates, +100 for numbers)
            source, tokens = scrub_mutate(source, tokens, scrub_indices[cursor], 1, :large)
            scrub_indices = tokens.each_index.select { |i| SCRUBABLE.include?(tokens[i].type) }
            cursor = cursor.clamp(0, scrub_indices.length - 1)
            redraw_scrub(source, tokens, scrub_indices, cursor, mode: scrub_mode)
          when "[", "{"  # [ — large (year for dates, -100 for numbers)
            source, tokens = scrub_mutate(source, tokens, scrub_indices[cursor], -1, :large)
            scrub_indices = tokens.each_index.select { |i| SCRUBABLE.include?(tokens[i].type) }
            cursor = cursor.clamp(0, scrub_indices.length - 1)
            redraw_scrub(source, tokens, scrub_indices, cursor, mode: scrub_mode)
          when "\r", "\n", "q", "\x03", "\x04"  # Enter, q, Ctrl-C, Ctrl-D → exit
            break
          end
        end
      end

      # Clean up: cursor is at bottom of drawn output, just move to fresh line
      print "\r\n"
      # Update session with mutated expression
      entry[:input] = source
    end

    def latest_scrub_entry
      @session_log.reverse.find { |entry| scrub_source?(entry[:input]) }
    end

    def scrub_source?(source)
      return false if source.to_s.include?("\n")

      tokenize_for_scrub(source).any? { |token| SCRUBABLE.include?(token.type) }
    end

    def tokenize_for_scrub(source)
      Tungsten.new_lexer(source).tokens
    rescue
      []
    end

    # Find [offset, length] spans for all scrubable tokens by scanning
    # the source string directly — avoids depending on lexer col tracking
    def scrub_spans(source, tokens, scrub_indices)
      spans = {}
      pos = 0
      tokens.each_with_index do |tok, i|
        next if tok.type == :EOF
        # Find this token's text in the source starting from pos
        text = scrub_token_text(tok)
        if text && !text.empty?
          idx = source.index(text, pos)
          if idx
            spans[i] = [idx, text.length] if scrub_indices.include?(i)
            pos = idx + text.length
            next
          end
        end
        # Non-matchable token — skip past whitespace/operators
        pos += 1 if pos < source.length
      end
      spans
    end

    def scrub_token_text(tok)
      case tok.type
      when :INT then tok.value.to_s
      when :FLOAT, :DECIMAL then tok.value.to_s
      when :RATIONAL then tok.value.to_s
      when :COLOR
        v = tok.value
        return nil unless v.is_a?(Array) && v.length >= 3
        v[3] == 255 ? format("#%02X%02X%02X", *v[0..2]) : format("#%02X%02X%02X%02X", *v)
      when :CHAR
        "U+#{tok.value.ord.to_s(16).upcase.rjust(4, "0")}"
      when :CURRENCY
        v = tok.value
        "#{v[1]}#{v[0]}"
      when :DURATION then tok.value.to_s
      when :QUANTITY then "#{tok.value[0]}#{tok.value[1]}"
      when :DATE, :DATETIME, :TIME, :MONTH then tok.value.to_s
      else nil
      end
    end

    def redraw_scrub(source, tokens, scrub_indices, cursor, mode: :evaluation)
      @scrub_lines_drawn ||= 0
      spans = scrub_spans(source, tokens, scrub_indices)
      highlighted_idx = scrub_indices[cursor]
      span = spans[highlighted_idx]
      return unless span

      hi_start, hi_len = span
      expr_display = source[0...hi_start].to_s +
                     "\e[7m" + source[hi_start, hi_len].to_s + "\e[0m" +
                     source[hi_start + hi_len..].to_s

      # Evaluate, capturing stdout
      result = nil
      captured = ""
      begin
        output = StringIO.new
        old_stdout = $stdout
        $stdout = output
        result = @interpreter.run(source)
      rescue => e
        result = "✗ #{e.message}"
      ensure
        $stdout = old_stdout
        captured = output.string
      end

      result_lines = scrub_result_lines(result, mode: mode)

      # Move cursor back to expression line and clear everything below
      if @scrub_lines_drawn > 1
        (@scrub_lines_drawn - 1).times { print "\e[A" }
      end
      print "\r\e[J"  # clear from cursor to end of screen

      # Draw: expression line
      lines_drawn = 1
      print "#{DIM}scrub>#{RESET} #{expr_display}"

      # Stdout output (if any)
      unless captured.empty?
        captured.each_line do |line|
          print "\r\n#{DIM}  │#{RESET} #{line.chomp}"
          lines_drawn += 1
        end
      end

      result_lines.each do |line|
        print "\r\n#{line}"
        lines_drawn += 1
      end

      @scrub_lines_drawn = lines_drawn
      $stdout.flush
    end

    def scrub_result_lines(result, mode:)
      if result.is_a?(String) && result.start_with?("✗")
        return ["#{DIM}    =>#{RESET} #{result}"]
      end

      return @interpreter.inspect_runtime_value(result).lines.map(&:chomp) if mode == :inspection

      ["#{DIM}    =>#{RESET} #{format_value(result)}"]
    end

    def scrub_mutate(source, tokens, token_idx, direction, magnitude = :small)
      tok = tokens[token_idx]
      scrub_indices = tokens.each_index.select { |i| SCRUBABLE.include?(tokens[i].type) }
      spans = scrub_spans(source, tokens, scrub_indices)
      span = spans[token_idx]
      return [source, tokens] unless span
      start, len = span

      # Magnitude: :small (day/±1), :medium (month/±10), :large (year/±100)
      step = case magnitude
             when :small then direction
             when :medium then direction * 10
             when :large then direction * 100
             end

      new_text = case tok.type
        when :INT
          (tok.value.to_i + step).to_s
        when :FLOAT, :DECIMAL
          (tok.value.to_f + step * 0.1).round(4).to_s
        when :RATIONAL
          num, den = tok.value.to_s.split("/").map(&:to_i)
          "#{num + step}/#{den}"
        when :COLOR
          v = tok.value.dup
          v[0] = (v[0] + step) % 256
          v[3] == 255 ? format("#%02X%02X%02X", *v[0..2]) : format("#%02X%02X%02X%02X", *v)
        when :CHAR
          cp = tok.value.ord + step
          "U+#{cp.to_s(16).upcase.rjust(4, "0")}"
        when :DATE
          d = ::Date.parse(tok.value.to_s)
          d = case magnitude
              when :small then d + direction           # ±1 day
              when :medium then d >> direction          # ±1 month
              when :large then d >> (direction * 12)    # ±1 year
              end
          d.strftime("%Y-%m-%d")
        when :DATETIME
          d = ::Date.parse(tok.value.to_s.split("T").first)
          d = case magnitude
              when :small then d + direction
              when :medium then d >> direction
              when :large then d >> (direction * 12)
              end
          tok.value.to_s.sub(/\A\d{4}-\d{2}-\d{2}/, d.strftime("%Y-%m-%d"))
        when :TIME
          t = tok.value.to_s.split(":")
          h, m, s = t[0].to_i, t[1].to_i, (t[2] || "0").to_i
          secs = case magnitude
                 when :small then direction * 60     # ±1 minute
                 when :medium then direction * 3600  # ±1 hour
                 when :large then direction * 60     # ±1 minute (no bigger unit)
                 end
          total = (h * 3600 + m * 60 + s + secs) % 86400
          format("%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        when :MONTH
          d = ::Date.parse(tok.value.to_s + "-01")
          d = case magnitude
              when :small, :medium then d >> direction       # ±1 month
              when :large then d >> (direction * 12)          # ±1 year
              end
          d.strftime("%Y-%m")
        else
          return [source, tokens]
        end

      new_source = source[0...start] + new_text + source[start + len..]
      new_tokens = tokenize_for_scrub(new_source)

      [new_source, new_tokens]
    end

    def ip4_info(ip)
      octets = ip.to_s.split(".").map(&:to_i)
      a = octets[0]
      if a == 10 || (a == 172 && octets[1] >= 16 && octets[1] <= 31) || (a == 192 && octets[1] == 168)
        "private"
      elsif a == 127
        "loopback"
      elsif a == 0
        "unspecified"
      elsif a < 128
        "Class A"
      elsif a < 192
        "Class B"
      elsif a < 224
        "Class C"
      elsif a < 240
        "Class D (multicast)"
      else
        "Class E (reserved)"
      end
    end

    def cidr4_info(cidr)
      addr = cidr.value
      prefix = addr.respond_to?(:prefix) ? addr.prefix : addr.to_s.scan(%r{/(\d+)}).flatten.first&.to_i
      prefix ||= cidr.to_s.scan(%r{/(\d+)}).flatten.first&.to_i || 0
      hosts = prefix < 31 ? (2**(32 - prefix) - 2) : (prefix == 31 ? 2 : 1)
      "#{ip4_info(cidr)} /#{prefix} (#{hosts} hosts)"
    end

    def uuid_info(uuid)
      s = uuid.to_s
      version = s[14]&.to_i
      version ? "v#{version}" : ""
    end

    def format_ai_response(text)
      text = clean_ai_text(text)
      rendered = TTY::Markdown.parse(text, width: TTY::Screen.width)
      rendered
        .gsub("\e[33m", MAGENTA)
        .gsub("\e[93m", BRIGHT_MAGENTA)
        .gsub(/@[A-Za-z_]\w*/, "#{MAGENTA}\\0#{RESET}")
    rescue StandardError
      text
    end

    def clean_ai_text(text)
      text.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
    end

    # Format value without ANSI codes for session log / Claude context.
    def plain_value(value)
      format_value(value).gsub(/\e\[[0-9;]*[a-zA-Z]/, "")
    end

    # Walk back through the session log collecting the last entry, plus any
    # prior entries whose input references `_` (meaning they built on the
    # previous result). Stops as soon as an entry does not use `_`.
    def gather_context
      return [] if @session_log.empty?

      entries = []
      i = @session_log.length - 1
      loop do
        entry = @session_log[i]
        entries.unshift(entry)
        break unless i > 0 && (entry[:input].include?("_.") || entry[:input].include?("_ "))
        i -= 1
      end
      entries
    end

    def handle_claude_query(prompt)
      call_anthropic(prompt, model_id: MODELS["sonnet"][:id], label: "@claude")
    end

    def handle_ai_query(prompt)
      call_current_model(prompt, label: "@ai")
    end

    def handle_aiku_query(prompt)
      call_current_model(
        "#{AIKU_PROMPT_PREFIX}#{prompt}",
        label: "@aiku",
        local_allow_directives: false,
        local_response_directive: "a"
      )
    end

    def call_current_model(prompt, label:, local_allow_directives: true, local_response_directive: nil)
      config = MODELS[@ai_model]
      case config[:provider]
      when :local
        call_local_model(
          prompt,
          model_name: @ai_model,
          label: label,
          allow_directives: local_allow_directives,
          response_directive: local_response_directive
        )
      else
        call_anthropic(prompt, model_id: config[:id], label: label)
      end
    end

    def handle_model_command(args)
      args = args.to_s.strip
      if args.empty?
        puts "#{BOLD}Current model:#{RESET} #{@ai_model} #{DIM}— #{MODELS[@ai_model][:label]}#{RESET}"
        puts
        puts "#{BOLD}Available:#{RESET}"
        MODELS.each do |name, config|
          marker = name == @ai_model ? " #{GREEN}◀#{RESET}" : ""
          puts "  #{name.ljust(8)} #{DIM}#{config[:label]}#{RESET}#{marker}"
        end
        puts
        puts "#{DIM}Use /model NAME to switch. Local models start a background server for @ai.#{RESET}"
      elsif args == "status"
        print_model_status
      elsif args == "stop"
        if local_model?(@ai_model)
          stop_model_server(@ai_model)
        else
          puts "#{DIM}  no local model selected#{RESET}"
        end
      elsif MODELS.key?(args)
        return unless ensure_model_available(args)

        @ai_model = args
        suffix = local_model?(args) ? "server ready - use @ai ..." : MODELS[args][:label]
        puts "#{DIM}  model:#{RESET} #{args} #{DIM}(#{suffix})#{RESET}"
      else
        puts "#{BRIGHT_RED}Unknown model: #{args}#{RESET}"
        puts "#{DIM}Available: #{(MODELS.keys + %w[status stop]).join(", ")}#{RESET}"
      end
    end

    def ensure_model_available(model_name)
      return true unless local_model?(model_name)

      start_model_server(model_name)
    end

    def local_model?(model_name)
      MODELS.dig(model_name, :provider) == :local
    end

    def print_model_status
      puts "#{BOLD}Current model:#{RESET} #{@ai_model} #{DIM}— #{MODELS[@ai_model][:label]}#{RESET}"
      local_names = MODELS.select { |_, config| config[:provider] == :local }.keys
      return if local_names.empty?

      puts
      puts "#{BOLD}Local servers:#{RESET}"
      local_names.each do |name|
        state = server_alive?(@model_servers[name]) ? "running" : "stopped"
        puts "  #{name.ljust(8)} #{DIM}#{state}#{RESET}"
      end
    end

    def start_model_server(model_name)
      existing = @model_servers[model_name]
      return true if server_alive?(existing)

      config = MODELS[model_name]
      spinner = start_spinner

      begin
        stdin, stdout, stderr, wait_thread = Open3.popen3(*config[:command], chdir: REPO_ROOT)
        @model_servers[model_name] = {
          stdin: stdin,
          stdout: stdout,
          stderr: stderr,
          wait_thread: wait_thread
        }
        ready = Timeout.timeout(LOCAL_MODEL_READY_TIMEOUT) { stdout.gets }
      rescue StandardError => e
        stop_spinner(spinner)
        stop_model_server(model_name)
        puts "#{DIM}  #{model_name}#{RESET} #{BRIGHT_RED}✗ #{e.message}#{RESET}"
        return false
      end

      stop_spinner(spinner)
      return true if ready&.strip == "READY"

      msg = ready ? "unexpected startup output: #{ready.strip}" : "server exited before READY"
      stop_model_server(model_name)
      puts "#{DIM}  #{model_name}#{RESET} #{BRIGHT_RED}✗ #{msg}#{RESET}"
      false
    end

    def server_alive?(server)
      server && server[:wait_thread]&.alive?
    end

    def stop_model_server(model_name)
      server = @model_servers.delete(model_name)
      return unless server

      server[:stdin]&.close unless server[:stdin]&.closed?
      server[:stdout]&.close unless server[:stdout]&.closed?
      server[:stderr]&.close unless server[:stderr]&.closed?
      wait_thread = server[:wait_thread]
      if wait_thread&.alive?
        Process.kill("TERM", wait_thread.pid)
        Timeout.timeout(2) { wait_thread.join }
      end
    rescue StandardError
      nil
    end

    def stop_all_model_servers
      @model_servers&.keys&.each { |name| stop_model_server(name) }
    end

    def call_local_model(prompt, model_name:, label:, allow_directives:, response_directive:)
      return unless ensure_model_available(model_name)

      wire_prompt, prompt_directive = local_model_prompt_parts(prompt, allow_directives:)
      directive = response_directive || prompt_directive
      server = @model_servers[model_name]
      spinner = start_spinner

      begin
        response = request_local_model(server, wire_prompt)
      rescue StandardError => e
        stop_spinner(spinner)
        stop_model_server(model_name)
        puts "#{DIM}  #{label}#{RESET} #{BRIGHT_RED}✗ #{e.message}#{RESET}"
        return
      end

      stop_spinner(spinner)
      text = clean_local_model_response(unescape_model_response(response), directive:)
      puts format_ai_response(text)
    end

    def request_local_model(server, prompt)
      raise "local model server is not running" unless server_alive?(server)

      server[:stdin].puts(prompt)
      server[:stdin].flush
      response = Timeout.timeout(LOCAL_MODEL_RESPONSE_TIMEOUT) { server[:stdout].gets }
      raise "local model server closed" unless response

      response.chomp
    end

    def local_model_prompt(prompt, allow_directives: true)
      local_model_prompt_parts(prompt, allow_directives:).first
    end

    def local_model_prompt_parts(prompt, allow_directives: true)
      text = prompt.to_s.gsub(/[ \t]*\r?\n[ \t]*/, " ").strip
      directive = nil

      if allow_directives && text.match?(/\s*:\s*[apsw]\z/)
        directive = text[/[apsw]\z/]
        text = text.sub(/\s*:\s*[apsw]\z/, "").rstrip
      end

      prefix = LOCAL_MODEL_PROMPT_DIRECTIVES[directive]
      [prefix ? "#{prefix} #{text}" : text, directive]
    end

    def unescape_model_response(text)
      text.to_s.gsub(/\\[nr]/) { |match| match == "\\n" ? "\n" : "\r" }
    end

    def clean_local_model_response(text, directive: nil)
      paragraphs = clean_ai_text(text)
        .gsub("\r\n", "\n")
        .split(/\n{2,}/)
        .map { |paragraph| paragraph.strip.sub(/\AAnswer:\s*/i, "").sub(/\A\?+\s*/, "") }
        .reject(&:empty?)

      return "" if paragraphs.empty?
      return paragraphs.join("\n\n") if directive == "a"

      paragraph = paragraphs.first
      case directive
      when "s"
        first_sentence(paragraph)
      when "w"
        one_word_answer(paragraph)
      else
        paragraph
      end
    end

    def first_sentence(text)
      text.to_s[/\A.*?[.!?](?=\s|\z)/m].to_s.then { |sentence| sentence.empty? ? text.to_s.strip : sentence.strip }
    end

    def one_word_answer(text)
      sentence = first_sentence(text)
      matches = sentence.scan(/\b(?:is|are|was|were|means|equals)\s+([[:alpha:]][[:alpha:]'.-]*)/i)
      word = matches.last&.first || sentence[/[[:alpha:]][[:alpha:]'.-]*/].to_s
      word.sub(/\A['".]+/, "").sub(/['".,;:!?]+\z/, "")
    end

    def call_anthropic(prompt, model_id:, label:)
      api_key = ENV["ANTHROPIC_API_KEY"]

      unless api_key
        puts "#{DIM}  #{label}#{RESET} #{BRIGHT_RED}✗ ANTHROPIC_API_KEY not set#{RESET}"
        puts "#{DIM}    get a key at console.anthropic.com/settings/keys#{RESET}"
        return
      end

      spinner = start_spinner

      begin
        uri = URI("https://api.anthropic.com/v1/messages")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 60

        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["anthropic-version"] = "2023-06-01"
        req["x-api-key"] = api_key

        system_prompt = +"You are a helpful assistant embedded in wit, the Tungsten language REPL. " \
                          "Tungsten is an OO language implemented in Ruby. " \
                          "Give concise, practical answers — prefer code examples when relevant."
        context = gather_context
        if context.any?
          system_prompt << "\n\nRecent REPL session:\n"
          context.each { |e| system_prompt << "> #{e[:input]}\n  => #{e[:result]}\n" }
        end

        req.body = JSON.generate({
          model: model_id,
          max_tokens: 2048,
          system: system_prompt,
          messages: [{ role: "user", content: prompt }]
        })

        response = http.request(req)
        data = JSON.parse(response.body)
      rescue => e
        stop_spinner(spinner)
        puts "#{DIM}  #{label}#{RESET} #{BRIGHT_RED}✗ #{e.message}#{RESET}"
        return
      end

      stop_spinner(spinner)

      if response.code == "200"
        text = data.dig("content", 0, "text") || ""
        puts format_ai_response(text)
      else
        msg = data.dig("error", "message") || response.body
        puts "#{DIM}  #{label}#{RESET} #{BRIGHT_RED}✗ #{msg}#{RESET}"
      end
    end

    def start_spinner
      @spinning = true
      verb = VERBS.sample

      Thread.new do
        i = 0
        while @spinning
          char = SPINNER[i % SPINNER.size]
          _, cols = terminal_size
          label = " #{char} #{verb}… "
          fill = "─" * [cols - label.length, 0].max
          prefix = i.zero? ? "\n" : ""
          $stderr.print "#{prefix}\r#{YELLOW}#{label}#{RESET}#{DIM}#{fill}#{RESET}"
          $stderr.flush
          sleep 0.2
          i += 1
        end
        $stderr.print "\r\e[2K"
        $stderr.flush
      end
    end

    def stop_spinner(thread)
      @spinning = false
      thread&.join
    end

    def print_error(error)
      if error.is_a?(Tungsten::Error) && (error.location || error.source_code)
        reporter = ErrorReporter.new(color: $stdout.tty? && !ENV["NO_COLOR"])
        puts reporter.format(error)
      else
        label = case error
                when DimensionError then "dimension error"
                when Tungsten::Error then "error"
                else error.class.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1 \2').downcase
                end
        puts "#{DIM}  =>#{RESET} #{BRIGHT_RED}✗ #{label}: #{error.message}#{RESET}"
      end
    end

    def print_result(value)
      formatted = format_value(value)
      puts "#{DIM}  =>#{RESET} #{formatted}"
    end

    # ── Value formatting ──────────────────────────────────────────────

    def format_value(value, depth = 0)
      case value
      when nil
        "#{DIM}nil#{RESET}"
      when true, false
        "#{MAGENTA}#{value}#{RESET}"
      when Integer
        "#{MAGENTA}#{value}#{RESET}"
      when Float
        "#{CYAN}#{value}#{RESET}"
      when BigDecimal
        "#{BRIGHT_YELLOW}#{value.to_s("F")}#{RESET}"
      when String
        "#{WHITE}\"#{value}\"#{RESET}"
      when Symbol
        "#{YELLOW}:#{value}#{RESET}"
      when Array
        format_array(value, depth)
      when Hash
        format_hash(value, depth)
      when Range
        "#{BRIGHT_CYAN}#{value}#{RESET}"
      when Runtime::WObject
        format_wobject(value, depth)
      when Runtime::WClass
        "#{BOLD}#{YELLOW}<#{value.name}>#{RESET}"
      when Runtime::RawWValue
        "#{CYAN}#{value.raw}#{RESET}"
      when Tungsten::AST::Def
        args = value.args&.map { |a| a.name.to_s }&.join(", ") || ""
        "#{DIM}fn#{RESET} #{CYAN}#{value.name}#{RESET}#{DIM}(#{args})#{RESET}"
      when Tungsten::Key
        "#{CYAN}#{value.inspect}#{RESET}"
      when Tungsten::Color
        "#{value.ansi_swatch(" #{value} ")}"
      when Tungsten::Date
        d = ::Date.parse(value.to_s) rescue nil
        if d
          "#{CYAN}#{d.strftime("%a, %b %-d, %Y")}#{RESET}"
        else
          "#{CYAN}#{value}#{RESET}"
        end
      when Tungsten::IP4
        "#{CYAN}#{value}#{RESET} #{DIM}#{ip4_info(value)}#{RESET}"
      when Tungsten::CIDR4
        prefix = value.value.respond_to?(:prefix) ? value.value.prefix : 0
        "#{CYAN}#{value}/#{prefix}#{RESET} #{DIM}#{cidr4_info(value)}#{RESET}"
      when Rational
        approx = value.to_f
        "#{CYAN}#{value}#{RESET} #{DIM}≈ #{approx.round(6)}#{RESET}"
      when Tungsten::UUID
        "#{CYAN}#{value}#{RESET} #{DIM}#{uuid_info(value)}#{RESET}"
      when Tungsten::Sandwich
        value.to_s
      when Tungsten::Literal
        "#{CYAN}#{value}#{RESET}"
      else
        "#{WHITE}#{value}#{RESET}"
      end
    end

    def format_array(arr, depth)
      return "#{DIM}[]#{RESET}" if arr.empty?
      return "#{DIM}[#{RESET}#{arr.length} items#{DIM}]#{RESET}" if depth >= 2 || arr.length > 20

      inner = arr.map { |v| format_value(v, depth + 1) }.join("#{DIM}, #{RESET}")
      "#{DIM}[#{RESET}#{inner}#{DIM}]#{RESET}"
    end

    def format_hash(hash, depth)
      return "#{DIM}{}#{RESET}" if hash.empty?
      return "#{DIM}{#{RESET}#{hash.length} entries#{DIM}}#{RESET}" if depth >= 2 || hash.length > 5

      inner = hash.map do |k, v|
        "#{format_value(k, depth + 1)}#{DIM}: #{RESET}#{format_value(v, depth + 1)}"
      end.join("#{DIM}, #{RESET}")
      "#{DIM}{#{RESET}#{inner}#{DIM}}#{RESET}"
    end

    def format_wobject(obj, depth)
      cls = "#{BOLD}#{YELLOW}#{obj.w_class.name}#{RESET}"
      ivars = obj.instance_vars
      return "#{cls}#{DIM}()#{RESET}" if ivars.empty?
      return "#{cls}#{DIM}(…)#{RESET}" if depth >= 2

      pairs = ivars.map do |k, v|
        "#{CYAN}@#{k}#{RESET}#{DIM}=#{RESET}#{format_value(v, depth + 1)}"
      end.join(" ")
      "#{cls}#{DIM}(#{RESET}#{pairs}#{DIM})#{RESET}"
    end
  end
end
