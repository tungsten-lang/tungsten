RSpec.describe Tungsten::REPL do
  let(:repl) { described_class.new }

  # Simulate Reline's callback: joins lines with "\n" and appends "\n"
  def buffer(*lines)
    lines.join("\n") + "\n"
  end

  def capture_stdout
    previous = $stdout
    captured = StringIO.new
    $stdout = captured
    yield
    captured.string
  ensure
    $stdout = previous
  end

  describe Tungsten::KittyFilter do
    let(:fake_io_class) do
      Class.new do
        attr_reader :wait_calls

        def initialize(bytes)
          @bytes = bytes.dup
          @wait_calls = 0
        end

        def getbyte
          @bytes.shift
        end

        def wait_readable(*)
          @wait_calls += 1
          nil
        end
      end
    end

    it "treats buffered escape-sequence bytes as immediately readable" do
      io = fake_io_class.new([0x1B, 0x5B, 0x41])
      filter = described_class.new(io)

      expect(filter.getbyte).to eq(0x1B)
      expect(filter.wait_readable(0)).to equal(io)
      expect(io.wait_calls).to eq(0)
      expect(filter.getbyte).to eq(0x5B)
      expect(filter.getbyte).to eq(0x41)
    end
  end

  describe "#code_complete?" do
    subject { repl.send(:code_complete?, buf) }

    context "single-line expressions" do
      it("integer")   { expect(repl.send(:code_complete?, buffer("42"))).to be true }
      it("string")    { expect(repl.send(:code_complete?, buffer('"hello"'))).to be true }
      it("variable")  { expect(repl.send(:code_complete?, buffer("x = 10"))).to be true }
      it("call")      { expect(repl.send(:code_complete?, buffer("puts(42)"))).to be true }
      it("empty")     { expect(repl.send(:code_complete?, buffer(""))).to be true }
      it("shell command") { expect(repl.send(:code_complete?, buffer("!printf '('"))).to be true }
      it("paste command") { expect(repl.send(:code_complete?, buffer("/paste"))).to be true }
    end

    context "block openers wait for body" do
      it("if")     { expect(repl.send(:code_complete?, buffer("if true"))).to be false }
      it("while")  { expect(repl.send(:code_complete?, buffer("while x < 3"))).to be false }
      it("elsif")  { expect(repl.send(:code_complete?, buffer("if false", "  1", "elsif true"))).to be false }
      it("else")   { expect(repl.send(:code_complete?, buffer("if false", "  1", "else"))).to be false }
      it("case")   { expect(repl.send(:code_complete?, buffer("case x"))).to be false }
      it("when")   { expect(repl.send(:code_complete?, buffer("case x", "when 1"))).to be false }
      it("unless") { expect(repl.send(:code_complete?, buffer("unless done"))).to be false }
      it("with")   { expect(repl.send(:code_complete?, buffer("with x in list"))).to be false }
      it("begin")  { expect(repl.send(:code_complete?, buffer("begin"))).to be false }
      it("rescue") { expect(repl.send(:code_complete?, buffer("begin", "  risky", "rescue"))).to be false }
      it("ensure") { expect(repl.send(:code_complete?, buffer("begin", "  risky", "ensure"))).to be false }
    end

    context "-> and + open blocks" do
      it("function def") { expect(repl.send(:code_complete?, buffer("-> double(x)"))).to be false }
      it("class def")    { expect(repl.send(:code_complete?, buffer("+ Dog"))).to be false }
    end

    context "indented lines stay incomplete" do
      it "body after if" do
        expect(repl.send(:code_complete?, buffer("if true", "  42"))).to be false
      end

      it "body after function def" do
        expect(repl.send(:code_complete?, buffer("-> foo(x)", "  x * 2"))).to be false
      end
    end

    context "single blank line does NOT terminate" do
      it "blank line within indented block" do
        expect(repl.send(:code_complete?, buffer("if true", "  42", ""))).to be false
      end

      it "blank line between indented lines" do
        expect(repl.send(:code_complete?, buffer("if true", "  a", "", "  b"))).to be false
      end
    end

    context "two blank lines terminate" do
      it "after indented body" do
        expect(repl.send(:code_complete?, buffer("if true", "  42", "", ""))).to be true
      end

      it "after function def body" do
        expect(repl.send(:code_complete?, buffer("-> foo(x)", "  x * 2", "", ""))).to be true
      end

      it "after nested block" do
        expect(repl.send(:code_complete?, buffer("-> f(n)", "  if n < 2", "    n", "", ""))).to be true
      end
    end

    context "unmatched brackets stay incomplete" do
      it("open paren")   { expect(repl.send(:code_complete?, buffer("foo(1,"))).to be false }
      it("open bracket")  { expect(repl.send(:code_complete?, buffer("[1, 2,"))).to be false }
      it("open brace")    { expect(repl.send(:code_complete?, buffer("{a: 1,"))).to be false }
      it("matched paren") { expect(repl.send(:code_complete?, buffer("foo(1, 2)"))).to be true }
    end

    context "keywords inside strings don't trigger block opener" do
      it "if inside string" do
        expect(repl.send(:code_complete?, buffer('<< "check if true"'))).to be true
      end

      it "elsif inside string" do
        expect(repl.send(:code_complete?, buffer('<< "true from elsif"'))).to be true
      end

      it "while inside string" do
        expect(repl.send(:code_complete?, buffer('x = "wait while loading"'))).to be true
      end
    end
  end

  describe "#calc_indent" do
    def indent(lines, line_index, is_newline)
      repl.send(:calc_indent, lines, line_index, 0, is_newline)
    end

    context "new line after block opener" do
      it "indents +2 after if" do
        expect(indent(["if true", ""], 1, true)).to eq 2
      end

      it "indents +2 after while" do
        expect(indent(["while x < 3", ""], 1, true)).to eq 2
      end

      it "indents +2 after ->" do
        expect(indent(["-> foo(x)", ""], 1, true)).to eq 2
      end

      it "indents +2 after + Class" do
        expect(indent(["+ Dog", ""], 1, true)).to eq 2
      end

      it "indents +2 after nested block opener" do
        expect(indent(["if true", "  if false", ""], 2, true)).to eq 4
      end

      it "indents +2 after else" do
        expect(indent(["if true", "  1", "else", ""], 3, true)).to eq 2
      end

      it "indents +2 after elsif" do
        expect(indent(["if false", "  1", "elsif true", ""], 3, true)).to eq 2
      end
    end

    context "new line preserves indent" do
      it "stays at same indent after body line" do
        expect(indent(["if true", "  42", ""], 2, true)).to eq 2
      end

      it "stays at same indent after blank line" do
        expect(indent(["if true", "  42", "", ""], 3, true)).to eq 2
      end

      it "stays at nested indent after blank line" do
        expect(indent(["-> f(n)", "  if n < 2", "    n", "", ""], 4, true)).to eq 4
      end
    end

    context "dedent keywords snap back" do
      it "else dedents to if level" do
        expect(indent(["if true", "  42", "  else"], 2, false)).to eq 0
      end

      it "elsif dedents to if level" do
        expect(indent(["if true", "  42", "  elsif"], 2, false)).to eq 0
      end

      it "rescue dedents to begin level" do
        expect(indent(["begin", "  risky", "  rescue"], 2, false)).to eq 0
      end

      it "when dedents to case level" do
        expect(indent(["case x", "  when 1", "    a", "  when"], 3, false)).to eq 0
      end

      it "nested else dedents to inner if level" do
        expect(indent(["-> f(x)", "  if true", "    42", "    else"], 3, false)).to eq 2
      end
    end

    context "non-dedent keywords don't change indent" do
      it "preserves current indent for regular content" do
        expect(indent(["if true", "  x = 42"], 1, false)).to eq 2
      end
    end
  end

  describe "#opens_block?" do
    def opens?(str)
      repl.send(:opens_block?, str)
    end

    it("if")     { expect(opens?("if x > 0")).to be true }
    it("while")  { expect(opens?("while true")).to be true }
    it("else")   { expect(opens?("else")).to be true }
    it("elsif")  { expect(opens?("elsif x")).to be true }
    it("case")   { expect(opens?("case x")).to be true }
    it("when")   { expect(opens?("when 1")).to be true }
    it("begin")  { expect(opens?("begin")).to be true }
    it("rescue") { expect(opens?("rescue")).to be true }
    it("ensure") { expect(opens?("ensure")).to be true }
    it("unless") { expect(opens?("unless done")).to be true }
    it("with")   { expect(opens?("with x in list")).to be true }
    it("->")     { expect(opens?("-> foo(x)")).to be true }
    it("+ Class") { expect(opens?("+ Dog")).to be true }

    it("assignment")  { expect(opens?("x = 10")).to be false }
    it("call")        { expect(opens?("puts(42)")).to be false }
    it("string")      { expect(opens?('<< "if true"')).to be false }
    it("keyword in string") { expect(opens?('x = "while loading"')).to be false }
  end

  describe "#format_value" do
    def fmt(value)
      # Strip ANSI codes for easier assertions
      repl.send(:format_value, value).gsub(/\e\[[0-9;]*m/, "")
    end

    it("nil")     { expect(fmt(nil)).to eq "nil" }
    it("true")    { expect(fmt(true)).to eq "true" }
    it("false")   { expect(fmt(false)).to eq "false" }
    it("integer") { expect(fmt(42)).to eq "42" }
    it("float")   { expect(fmt(3.14)).to eq "3.14" }
    it("string")  { expect(fmt("hello")).to eq '"hello"' }
    it("symbol")  { expect(fmt(:foo)).to eq ":foo" }
    it("raw wvalue") { expect(fmt(Tungsten::Runtime::RawWValue.new(0xFFF9_0000_0000_001C))).to eq "u0xFFF900000000001C" }
    it("empty array")  { expect(fmt([])).to eq "[]" }
    it("small array")  { expect(fmt([1, 2, 3])).to eq "[1, 2, 3]" }
    it("empty hash")   { expect(fmt({})).to eq "{}" }
    it("range")   { expect(fmt(1..5)).to eq "1..5" }
  end

  describe "#format_ai_response" do
    it "preserves @var magenta coloring after tty-markdown render" do
      allow(TTY::Markdown).to receive(:parse).and_return("@foo is cool")
      result = repl.send(:format_ai_response, "@foo is cool")
      expect(result).to include("\e[35m@foo\e[0m")
    end

    it "passes terminal width to tty-markdown" do
      expect(TTY::Markdown).to receive(:parse)
        .with(anything, hash_including(width: anything))
        .and_return("")
      repl.send(:format_ai_response, "# hi")
    end

    it "handles empty string without raising" do
      expect { repl.send(:format_ai_response, "") }.not_to raise_error
    end

    it "scrubs invalid UTF-8 before markdown rendering" do
      invalid = "bad \xFF bytes".b

      expect(repl.send(:clean_ai_text, invalid)).to eq("bad ? bytes")
    end

    it "falls back to raw text when markdown rendering fails" do
      allow(TTY::Markdown).to receive(:parse).and_raise(ArgumentError, "bad markdown")

      expect(repl.send(:format_ai_response, "plain text")).to eq("plain text")
    end
  end

  describe "local model commands" do
    it "starts and selects a local model" do
      allow(repl).to receive(:start_model_server).with("lightning").and_return(true)

      output = capture_stdout { repl.send(:handle_model_command, "lightning") }.gsub(/\e\[[0-9;]*m/, "")

      expect(repl.instance_variable_get(:@ai_model)).to eq("lightning")
      expect(output).to include("model: lightning")
      expect(output).to include("server ready")
    end

    it "routes @ai through the selected local model" do
      repl.instance_variable_set(:@ai_model, "lightning")

      expect(repl).to receive(:call_local_model).with(
        "hello",
        model_name: "lightning",
        label: "@ai",
        allow_directives: true,
        response_directive: nil
      )

      repl.send(:handle_ai_query, "hello")
    end

    it "routes @aiku through the selected local model with the aiku prompt" do
      repl.instance_variable_set(:@ai_model, "lightning")
      prompt = "#{described_class::AIKU_PROMPT_PREFIX}tomatoes"

      expect(repl).to receive(:call_local_model).with(
        prompt,
        model_name: "lightning",
        label: "@aiku",
        allow_directives: false,
        response_directive: "a"
      )

      repl.send(:handle_aiku_query, "tomatoes")
    end

    it "normalizes prompt lines for the stdin/stdout model protocol" do
      expect(repl.send(:local_model_prompt, "hello\n  there")).to eq("hello there")
    end

    it "uses an explicit paragraph directive for local prompts ending in : p" do
      expect(repl.send(:local_model_prompt, "tomatoes: p")).to eq("Answer in one paragraph. tomatoes")
    end

    it "uses an explicit short sentence directive for local prompts ending in : s" do
      expect(repl.send(:local_model_prompt, "hello there: s")).to eq("Answer in one short sentence. hello there")
    end

    it "uses an explicit one word directive for local prompts ending in : w" do
      expect(repl.send(:local_model_prompt, "capital of France: w")).to eq("Answer in one word. capital of France")
    end

    it "uses an explicit article directive for local prompts ending in : a" do
      expect(repl.send(:local_model_prompt, "tomatoes: a")).to eq("Write an article on: tomatoes")
    end

    it "trims local model responses after the first paragraph" do
      text = "Paris.\n\nThe capital of France is Paris again."

      expect(repl.send(:clean_local_model_response, text)).to eq("Paris.")
    end

    it "keeps the full first paragraph without a local response directive" do
      text = "The capital of France is Paris. It is a city located in the north of the country."

      expect(repl.send(:clean_local_model_response, text)).to eq(text)
    end

    it "trims local model responses after the first complete sentence for : s prompts" do
      text = "The capital of France is Paris. It is a city located in the north of the country, and it is"

      expect(repl.send(:clean_local_model_response, text, directive: "s")).to eq("The capital of France is Paris.")
    end

    it "trims local model responses to one word for : w prompts" do
      text = "The capital of France is Paris. It is a city located in the north of the country."

      expect(repl.send(:clean_local_model_response, text, directive: "w")).to eq("Paris")
    end

    it "keeps a direct one-word local response for : w prompts" do
      expect(repl.send(:clean_local_model_response, "Answer: Paris.", directive: "w")).to eq("Paris")
    end

    it "keeps all non-question-mark paragraphs for article responses" do
      text = "?\n\nFirst paragraph.\n\nSecond paragraph."

      expect(repl.send(:clean_local_model_response, text, directive: "a")).to eq("First paragraph.\n\nSecond paragraph.")
    end

    it "skips a bare question mark paragraph in local model responses" do
      text = "?\n\nParis.\n\nThe capital of France is Paris again."

      expect(repl.send(:clean_local_model_response, text)).to eq("Paris.")
    end

    it "strips leading question marks from local model responses" do
      text = "? The capital of France is Paris.\n\nThe capital of France is Paris again."

      expect(repl.send(:clean_local_model_response, text)).to eq("The capital of France is Paris.")
    end

    it "unescapes model response newlines" do
      expect(repl.send(:unescape_model_response, "one\\ntwo\\rthree")).to eq("one\ntwo\rthree")
    end
  end

  describe "completion and inline help" do
    it "completes runtime names, units, and methods" do
      capture_stdout { repl.send(:evaluate_and_display, "favorite_color = #ff0000") }

      expect(repl.send(:complete, "fav")).to include("favorite_color")
      expect(repl.send(:complete, "Arr")).to include("Array")
      expect(repl.send(:complete, "sele")).to include("select")
      expect(repl.send(:complete, "[1, 2, 3]/sele")).to include("select")
      expect(repl.send(:complete, "kW")).to include("kW")
      expect(repl.send(:complete, "./spe")).to include("./spec/")
    end

    it "only completes model names after /model" do
      expect(repl.send(:complete, "/model ")).to match_array(described_class::MODELS.keys)
      expect(repl.send(:complete, "/model l")).to eq(["lightning"])
      expect(repl.send(:complete, "/model st")).to eq([])
      expect(repl.send(:complete, "/model ./spe")).to eq([])
    end

    it "only completes model names after /model when called with Reline completion context" do
      expect(repl.send(:complete, "", "/model ", "")).to match_array(described_class::MODELS.keys)
      expect(repl.send(:complete, "l", "/model ", "")).to eq(["lightning"])
      expect(repl.send(:complete, "st", "/model ", "")).to eq([])
      expect(repl.send(:complete, "./spe", "/model ", "")).to eq([])
    end

    it "does not complete inside @ai prompts" do
      expect(repl.send(:complete, "@ai ")).to eq([])
      expect(repl.send(:complete, "capital", "@ai ", "")).to eq([])
      expect(repl.send(:complete, "tomatoes", "@aiku ", "")).to eq([])
    end

    it "shows dimmed inline signatures for method calls" do
      output = repl.send(:decorate_input, "[1, 2, 3].select(", complete: true)
      slash_output = repl.send(:decorate_input, "[1, 2, 3]/sqrt", complete: true)

      expect(output).to include("\e[2m  select(&block)\e[0m")
      expect(slash_output).to include("\e[2m  sqrt(...)\e[0m")
    end

    it "shows shell intent while typing bang commands" do
      expect(repl.send(:decorate_input, "!", complete: true)).to include("\e[95m  shell command\e[0m")
      expect(repl.send(:decorate_input, "!ls", complete: true)).to include("\e[95m  shell command\e[0m")
    end

    it "colors shell-mode command input yellow" do
      repl.instance_variable_set(:@shell_mode, true)

      expect(repl.send(:decorate_input, "printf hi\n", complete: true)).to eq("\e[33mprintf hi\e[0m\n")
    end
  end

  describe "shell and paste modes" do
    def line_editor(line = "")
      editor = Reline::LineEditor.new(Reline.core.config)
      editor.reset("wit> ")
      editor.set_current_line(line, line.bytesize)
      editor
    end

    it "toggles shell mode and runs shell commands" do
      output = capture_stdout do
        repl.send(:enter_shell_mode)
        repl.send(:handle_shell_mode_input, "printf wit-shell")
      end

      expect(output).not_to include("back to wit")
      expect(output).to include("wit-shell")
      expect(repl.instance_variable_get(:@shell_mode)).to be false
    end

    it "uses a yellow bang prompt for transient shell commands" do
      repl.instance_variable_set(:@shell_mode, true)

      expect(repl.send(:prompt)).to eq("\e[33m! \e[0m")
    end

    it "enters shell mode immediately when bang is typed first on the line" do
      repl.send(:setup_readline)
      editor = line_editor
      previous_repl = Thread.current[:tungsten_wit_repl]
      Thread.current[:tungsten_wit_repl] = repl

      editor.send(:self_insert, "!")

      expect(repl.instance_variable_get(:@shell_mode)).to be true
      expect(repl.instance_variable_get(:@shell_mode_one_shot)).to be true
      expect(repl.instance_variable_get(:@shell_mode_pending_notice)).to be false
      expect(editor.finished?).to be false
      expect(editor.line).to eq("")
      expect(editor.prompt_list.first).to eq("\e[33m! \e[0m")
    ensure
      Thread.current[:tungsten_wit_repl] = previous_repl
    end

    it "repaints the existing prompt frame when transient shell mode toggles in place" do
      repl.send(:setup_readline)
      repl.instance_variable_set(:@tty, true)
      allow(repl).to receive(:terminal_size).and_return([24, 8])
      editor = line_editor
      previous_repl = Thread.current[:tungsten_wit_repl]
      Thread.current[:tungsten_wit_repl] = repl

      shell_output = capture_stdout { editor.send(:self_insert, "!") }
      wit_output = capture_stdout { editor.send(:em_delete_prev_char, "\177") }

      expect(shell_output).to include("\e[33m────────\e[0m")
      expect(shell_output).to include("shell command · returns to wit after Enter")
      expect(wit_output).to include("\e[2m────────\e[0m")
      expect(wit_output).to include("Tab completions")
    ensure
      Thread.current[:tungsten_wit_repl] = previous_repl
    end

    it "keeps bang literal when it is not first on the line" do
      repl.send(:setup_readline)
      editor = line_editor("value")
      previous_repl = Thread.current[:tungsten_wit_repl]
      Thread.current[:tungsten_wit_repl] = repl

      editor.send(:self_insert, "!")

      expect(repl.instance_variable_get(:@shell_mode)).to be false
      expect(editor.finished?).to be false
      expect(editor.current_line).to eq("value!")
    ensure
      Thread.current[:tungsten_wit_repl] = previous_repl
    end

    it "exits transient shell mode when backspace is pressed on a blank line" do
      repl.send(:setup_readline)
      capture_stdout { repl.send(:enter_shell_mode) }
      editor = line_editor
      previous_repl = Thread.current[:tungsten_wit_repl]
      Thread.current[:tungsten_wit_repl] = repl

      editor.send(:em_delete_prev_char, "\177")

      expect(repl.instance_variable_get(:@shell_mode)).to be false
      expect(repl.instance_variable_get(:@shell_mode_one_shot)).to be false
      expect(repl.instance_variable_get(:@shell_mode_backspace_cancel)).to be false
      expect(editor.finished?).to be false
      expect(editor.line).to eq("")
      expect(editor.prompt_list.first).to eq("\e[35mwit\e[0m> ")
    ensure
      Thread.current[:tungsten_wit_repl] = previous_repl
    end

    it "keeps blank-line backspace inert outside transient shell mode" do
      repl.send(:setup_readline)
      editor = line_editor
      previous_repl = Thread.current[:tungsten_wit_repl]
      Thread.current[:tungsten_wit_repl] = repl

      editor.send(:em_delete_prev_char, "\177")

      expect(repl.instance_variable_get(:@shell_mode_backspace_cancel)).to be false
      expect(editor.finished?).to be false
      expect(editor.current_line).to eq("")
    ensure
      Thread.current[:tungsten_wit_repl] = previous_repl
    end

    it "does not remember transient shell interaction as wit history" do
      expect(repl.send(:remember_history?, "!")).to be false
      expect(repl.send(:persisted_history?, "!")).to be false
      Reline::HISTORY.clear
      Reline::HISTORY << "one"
      Reline::HISTORY << "!"
      Reline::HISTORY << "two"
      repl.send(:sanitize_history!)
      expect(Reline::HISTORY.to_a).to eq(["one", "two"])

      repl.instance_variable_set(:@shell_mode, true)
      expect(repl.send(:remember_history?, "exit")).to be false
      expect(repl.send(:remember_history?, "!")).to be false
      expect(repl.send(:remember_history?, "pwd")).to be false
      repl.instance_variable_set(:@shell_mode, false)
      expect(repl.send(:remember_history?, "pwd")).to be true
      expect(repl.send(:persisted_history?, "pwd")).to be true
    end

    it "colors shell mode prompt separators yellow" do
      repl.instance_variable_set(:@tty, true)
      repl.instance_variable_set(:@shell_mode, true)
      allow(repl).to receive(:terminal_size).and_return([24, 12])

      output = capture_stdout { repl.send(:print_separator) }

      expect(output).to include("\e[33m────────────\e[0m")
    end

    it "preserves pasted indentation exactly until /end" do
      source = repl.send(:read_paste_source, StringIO.new("if true\n  a = 1\n    b = 2\n/end\n"))

      expect(source).to eq("if true\n  a = 1\n    b = 2")
    end

    it "evaluates pasted source after collecting it verbatim" do
      output = capture_stdout do
        repl.send(:handle_paste_mode, io: StringIO.new("answer = 41\nanswer + 1\n/end\n"))
      end.gsub(/\e\[[0-9;]*m/, "")

      expect(output).to include("paste mode")
      expect(output).to include("=> 42")
    end
  end

  describe "? inspection" do
    def raw_inspect_output(query)
      capture_stdout { repl.send(:handle_inspection_query, query) }
    end

    def inspect_output(query)
      raw_inspect_output(query).gsub(/\e\[[0-9;]*m/, "")
    end

    def plain_inspect_output(query)
      raw_inspect_output(query).gsub(/\e\[[0-9;]*[a-zA-Z]/, "").delete("\r")
    end

    it "explains inline symbol wvalues pasted from LLVM IR" do
      output = inspect_output("u0xFFF9073656C6966B")

      expect(output).to include("u0xFFF9073656C6966B")
      expect(output).to include("tag      bits 63..48  0xFFF9")
      expect(output).to include("kind     bit 0        1                  symbol")
      expect(output).to include("mode     bits 3..1    5                  inline (5 bytes)")
      expect(output).to include("byte[0]  bits 11..4   0x66")
      expect(output).to match(/decoded\s+:files/)
    end

    it "explains slab-backed string references without pretending to know the contents" do
      output = inspect_output("u0xFFF900000000001C")

      expect(output).to include("u0xFFF900000000001C")
      expect(output).to include("mode     bits 3..1    6                  slab")
      expect(output).to include("slab     bits 27..4   0x000001")
      expect(output).to include("needs slab table to recover contents")
    end

    it "can inspect ordinary runtime values by re-encoding immediate ones" do
      output = inspect_output(":files")

      expect(output).to include("result   :files")
      expect(output).to include("type     Symbol")
      expect(output).to include("u0xFFF9073656C6966B")
      expect(output).to include("note                                     exact immediate encoding")
    end

    it "explains quantity aliases and custom dimensions" do
      pb_output = inspect_output("1pb")

      expect(pb_output).to include("result   1 pb")
      expect(pb_output).to include("type     Tungsten::Quantity")
      expect(pb_output).to include("unit     pb (peanutbutter)")
      expect(pb_output).to include("dimension peanutbutter")
      expect(pb_output).to include("expanded 1 peanutbutter")
      expect(pb_output).to include("aliases  pb, peanut butter")
      expect(pb_output).to include(%(wvalue   Quantity unit "peanutbutter" has no runtime WValue unit id))
      expect(pb_output).not_to include("not a self-contained immediate WValue")

      j_output = inspect_output("1j")

      expect(j_output).to include("result   1 j")
      expect(j_output).to include("unit     j (jelly)")
      expect(j_output).to include("dimension jelly")
      expect(j_output).to include("expanded 1 jelly")
      expect(j_output).to include("aliases  j, jam, grape jelly")
      expect(j_output).to include(%(wvalue   Quantity unit "jelly" has no runtime WValue unit id))
      expect(j_output).not_to include("not a self-contained immediate WValue")
    end

    it "explains derived quantity dimensions, expansion, and conversions" do
      output = inspect_output("1J")

      expect(output).to include("result   1 J")
      expect(output).to include("dimension energy (length²·mass/time²)")
      expect(output).to include("expanded 1 kg·m²/s²")
      expect(output).to include("converts eV, erg, cal, kcal, BTU, therm, kWh, ftlbf")
      expect(output).to include("etymology Named for James Prescott Joule")
      expect(output).to include("history  The joule became an international")
      expect(output).to include("u0xFFFDC28000000080")
      expect(output).to include("unit     bits 45..38  0x0A               unit id")
      expect(output).to include("note                                     exact immediate encoding")
    end

    it "draws color channels and color-space details" do
      literal_output = inspect_output("#ff0000")

      expect(literal_output).to include("result      #FF0000")
      expect(literal_output).to include("type     Tungsten::Color")
      expect(literal_output).to include("palette  complement")
      expect(literal_output).to include("#00FFFF")
      expect(literal_output).to include("u0xFFFE0FF0000FF000")
      expect(literal_output).to include("subtype  bits 47..45  0                  color")
      expect(literal_output).not_to include("not a self-contained immediate WValue")

      output = inspect_output("Color.rgb(255,128,0)")

      expect(output).to include("result      #FF8000")
      expect(output).to include("rgba     255, 128, 0, 255")
      expect(output).to include("hsl      30° 100% 50%")
      expect(output).to include("luma     151.4 · black text")
      expect(output).to include("red      ████████████████ 255")
      expect(output).to include("green    ████████░░░░░░░░ 128")
      expect(output).to include("blue     ░░░░░░░░░░░░░░░░ 0")
      expect(output).to include("u0xFFFE0FF8000FF000")
      expect(output).to include("subtype  bits 47..45  0                  color")
      expect(output).to include("note                                     exact immediate encoding")
      expect(output).not_to include("not a self-contained immediate WValue")
    end

    it "visualizes small arrays and hashes" do
      array_output = inspect_output("[1, 2, 3, 5, 8]")

      expect(array_output).to include("type     Array")
      expect(array_output).to include("size     5")
      expect(array_output).to include("layout   SmallArray candidate · u8[5] · 7 bytes")
      expect(array_output).to include("lowering normal Array unless compiler marks literal const_safe")
      expect(array_output).to include("spark")
      expect(array_output).not_to include("values")
      expect(array_output).to include("wvalue   Array object pointer is not known in wit; compiler may lower")

      hash_output = inspect_output("{name: \"Ada\", score: 42, active: true}")

      expect(hash_output).to include("type     Hash")
      expect(hash_output).to include("size     3")
      expect(hash_output).to include("table    key")
      expect(hash_output.lines.grep(/table|name|score|active/).all? { |line| line.chomp.length <= 80 }).to be true
    end

    it "shows method docs and source references" do
      doc_output = capture_stdout do
        repl.send(:handle_method_reference_query, "Array#select", mode: :doc)
      end
      source_output = inspect_output("Array#select")

      expect(doc_output).to include("method   Array#select")
      expect(doc_output).to include("sig      select(&block)")
      expect(doc_output).to include("doc      Returns a new Array")
      expect(doc_output).to include("location implementations/ruby/lib/tungsten/runtime/builtins.rb:")
      expect(doc_output).not_to include("/Users/erik/tungsten/")
      expect(source_output).to include("method   Array#select")
      expect(source_output).to include("source")
      expect(source_output).to include("define_method_builtin(\"select\")")
    end

    it "adds an 80-column calendar, season rail, and holiday art scene for dates" do
      output = plain_inspect_output("2025-07-04")

      expect(output).to include("\n\nFriday, July 4th, 2025")
      expect(output).to include("✿ [☀] ☙  ❄")
      expect(output).to include("[Day 185/365] Week 27")
      expect(output).to include("Independence Day")
      expect(output.lines.find { |line| line.start_with?("Independence Day") }).not_to include("^")
      expect(output).to include("Su   Mo   Tu   We   Th   Fr   Sa")
      expect(output).to include("---------------------------------")
      expect(output).to include("          01   02   03  [04]  05")
      expect(output).to include("--+--        --+--              --+--")
      expect(output).not_to include("first quarter")
      expect(output).to include("u0xFFFE87E972000000")
      expect(output).to include("subtype  bits 47..45  4                  date")
      expect(output).to include("year     bits 43..32  2025")

      scene_lines = output.lines.drop_while { |line| !line.start_with?("Friday,") }.take_while do |line|
        !line.start_with?("u0x")
      end
      expect(scene_lines.reject { |line| line == "\n" }.all? { |line| line.chomp.length == 80 }).to be true
    end

    it "colors holiday ascii art" do
      halloween_raw = raw_inspect_output("2024-10-31")
      halloween_output = halloween_raw.gsub(/\e\[[0-9;]*m/, "")

      expect(halloween_output).to include("Halloween")
      expect(halloween_output).to include(%(.-"""""""-.))
      expect(halloween_output).to include("/\\   /\\")
      expect(halloween_output).to include("(___)   (__)")
      expect(halloween_raw).to include("\e[38;5;208m.-\"\"\"\"\"\"\"-.\e[0m")
      expect(halloween_raw).to include("\e[33m/\\   /\\\e[0m")
      expect(halloween_raw).to include("\e[33m\\_/\\_/\\_/\e[0m")

      independence_raw = raw_inspect_output("2026" + "-07-04")
      independence_output = independence_raw.gsub(/\e\[[0-9;]*m/, "")

      expect(independence_output).to include("Independence Day")
      expect(independence_output).to include("\\|/           \\|/                \\|/")
      expect(independence_output).to include("--+--        --+--              --+--")
      expect(independence_output).to include("/|\\           /|\\                /|\\")
      expect(independence_output).not_to include("___/|\\___")

      edge_line = independence_output.lines.find { |line| line.include?("--+--        --+--") }.chomp
      expect(edge_line.length).to eq(80)
      expect(edge_line).to end_with("-")

      expect(independence_raw).to include("\e[31m\\|/\e[0m")
      expect(independence_raw).to include("\e[37m--\e[0m\e[31m+\e[0m\e[37m--\e[0m")
      expect(independence_raw).to include("\e[34m--\e[0m\e[37m+\e[0m\e[34m--\e[0m")

      valentine_raw = raw_inspect_output("2026-02-14")
      valentine_output = valentine_raw.gsub(/\e\[[0-9;]*m/, "")

      expect(valentine_output).to include("Valentine's Day")
      expect(valentine_output).to include(".----.     ♥♥♥♥♥ ♥♥♥♥♥")
      expect(valentine_output).to include("|love|    ♥♥♥♥♥♥♥♥♥♥♥♥♥")
      expect(valentine_output).not_to include("<3")
      expect(valentine_output).not_to include("ʕ")
      expect(valentine_raw).to include("\e[38;5;205m♥♥♥♥♥\e[0m")
      expect(valentine_raw).to include("\e[31m♥♥♥♥♥♥♥♥♥♥♥♥♥\e[0m")
      expect(valentine_raw).to include("\e[37m|love|\e[0m")
      expect(valentine_raw).to include("\e[35m♥♥♥\e[0m")

      st_patricks_raw = raw_inspect_output("2026-03-17")
      st_patricks_output = st_patricks_raw.gsub(/\e\[[0-9;]*m/, "")

      expect(st_patricks_output).to include("St. Patrick's Day")
      expect(st_patricks_output).to include("☘")
      expect(st_patricks_output).to include("~~~~~~~~~~~~~~~~~~~~~~~~")
      expect(st_patricks_output).to include(".-======-.  $")
      expect(st_patricks_output).to include("/ $ $ $ $ \\")
      expect(st_patricks_output).to include("\\________/")
      expect(st_patricks_raw).to include("\e[32m☘\e[0m")
      expect(st_patricks_raw).to include("\e[31m~~~~\e[0m")
      expect(st_patricks_raw).to include("\e[38;5;208m~~~~\e[0m")
      expect(st_patricks_raw).to include("\e[34m~~~~\e[0m")
      expect(st_patricks_raw).to include("\e[38;5;94m.-======-.\e[0m")

      easter_raw = raw_inspect_output("2026-04-05")
      easter_output = easter_raw.gsub(/\e\[[0-9;]*m/, "")

      expect(easter_output).to include("Easter")
      expect(easter_output).to include("(\\_/)")
      expect(easter_output).to include("/ >🥕")
      expect(easter_output).to include(".-.      .-.      .-.")
      expect(easter_output).to include("/ ~ \\    / ^ \\    / * \\")
      expect(easter_output).to include("\\___/    \\___/    \\___/")
      expect(easter_output).not_to include(".-\"\"\"\"\"-.")
      expect(easter_raw).to include("\e[35m.-.\e[0m")
      expect(easter_raw).to include("\e[33m/ ^ \\\e[0m")
      expect(easter_raw).to include("\e[36m\\___/\e[0m")

      christmas_raw = raw_inspect_output("2025-12-25")
      christmas_output = christmas_raw.gsub(/\e\[[0-9;]*m/, "")

      expect(christmas_output).to include("Christmas")
      expect(christmas_output).to include("o--o--o--o--o--o--o--o")
      expect(christmas_output).to include("/_o_o_\\")
      expect(christmas_output).to include("/_o_o_o_\\")
      expect(christmas_output).to include("/_________\\")
      expect(christmas_output).not_to include("[____]")
      expect(christmas_raw).to include("\e[33m*\e[0m")
      expect(christmas_raw).to include("\e[32m/_\\\e[0m")
      expect(christmas_raw).to include("\e[31mo\e[0m")
      expect(christmas_raw).to include("\e[38;5;94m|_|\e[0m")
      expect(christmas_raw).to include("\e[32m/_________\\\e[0m")
      expect(christmas_raw).to include("\e[36mo\e[0m")

      thanksgiving_raw = raw_inspect_output("2025-11-27")
      thanksgiving_output = thanksgiving_raw.gsub(/\e\[[0-9;]*m/, "")

      expect(thanksgiving_output).to include("Thanksgiving")
      expect(thanksgiving_output).to include("^^^  ^^^")
      expect(thanksgiving_output).to include(".-' \\|/ '-.")
      expect(thanksgiving_output).to include("--=  (o o)  =--")
      expect(thanksgiving_raw).to include("\e[38;5;196m^^^\e[0m")
      expect(thanksgiving_raw).to include("\e[38;5;208m^^^^^\e[0m")
      expect(thanksgiving_raw).to include("\e[38;5;214m--=\e[0m")
      expect(thanksgiving_raw).to include("\e[38;5;130m/( : )\\\e[0m")
    end

    it "keeps highlighted calendar days aligned to weekday columns" do
      output = inspect_output("2026-04-01")

      expect(output).to include("Su   Mo   Tu   We   Th   Fr   Sa")
      expect(output).to include("---------------------------------")
      expect(output).to include("              [01]  02   03   04")
      expect(output).to include("05   06   07   08   09   10   11")

      christmas_output = inspect_output("2025-12-25")
      header = christmas_output.lines.find { |line| line.include?("Su   Mo") }.rstrip
      highlighted_week = christmas_output.lines.find { |line| line.include?("[25]") }.rstrip

      expect(highlighted_week).to include("21   22   23   24  [25]  26   27")
      expect(highlighted_week.index("25")).to eq(header.index("Th"))
      expect(highlighted_week.index("26")).to eq(header.index("Fr"))
    end

    it "makes inspected date literals available for scrub mode" do
      inspect_output("2025-01-01")
      inspect_output("true")

      entry = repl.send(:latest_scrub_entry)
      expect(entry[:input]).to eq("2025-01-01")
      expect(entry[:mode]).to eq(:inspection)

      tokens = repl.send(:tokenize_for_scrub, entry[:input])
      date_idx = tokens.find_index { |token| token.type == :DATE }

      expect(repl.send(:scrub_mutate, entry[:input], tokens, date_idx, 1, :small).first).to eq("2025-01-02")
      expect(repl.send(:scrub_mutate, entry[:input], tokens, date_idx, 1, :medium).first).to eq("2025-02-01")
      expect(repl.send(:scrub_mutate, entry[:input], tokens, date_idx, 1, :large).first).to eq("2026-01-01")
    end

    it "redraws microscope output while scrubbing inspected values" do
      source = "2025-01-01"
      tokens = repl.send(:tokenize_for_scrub, source)
      date_idx = tokens.find_index { |token| token.type == :DATE }
      output = capture_stdout do
        repl.send(:redraw_scrub, source, tokens, [date_idx], 0, mode: :inspection)
      end.gsub(/\e\[[0-9;]*[a-zA-Z]/, "")

      expect(output).to include("scrub> 2025-01-01")
      expect(output).to include("result   2025-01-01")
      expect(output).to include("Su   Mo   Tu   We   Th   Fr   Sa")
      expect(output).to include("u0xFFFE87E910800000")
      expect(output).not_to include("=> 2025-01-01")
    end

    it "re-encodes date-times and durations when their fields fit" do
      date_time_output = inspect_output("2024-10-31T14:30:00Z")

      expect(date_time_output).to include("u0xFFFE87E8AFB9E000")
      expect(date_time_output).to include("subtype  bits 47..45  4                  date")
      expect(date_time_output).to include("hour     bits 22..18  14")
      expect(date_time_output).to include("minute   bits 17..12  30")
      expect(date_time_output).to include("tz       bits 5..0    0                  timezone offset")

      duration_output = inspect_output("2h15m")

      expect(duration_output).to include("u0xFFFF075DED9F6800")
      expect(duration_output).to include("mode     bit 47       0                  nanoseconds")
      expect(duration_output).to include("ns       bits 46..0   8100000000000      signed nanoseconds")
    end

    it "explains IPv4 and CIDR anatomy" do
      ip_output = inspect_output("192.168.1.1")

      expect(ip_output).to include("class    private RFC1918")
      expect(ip_output).to include("hex      0xC0A80101")
      expect(ip_output).to include("binary   11000000.10101000.00000001.00000001")
      expect(ip_output).to include("ptr      1.1.168.192.in-addr.arpa")
      expect(ip_output).to include("u0xFFFEAC0A80101000")
      expect(ip_output).to include("addr     bits 43..12  0xC0A80101         192.168.1.1")

      cidr_output = inspect_output("192.168.1.0/24")

      expect(cidr_output).to include("prefix   /24")
      expect(cidr_output).to include("netmask  255.255.255.0")
      expect(cidr_output).to include("network  192.168.1.0")
      expect(cidr_output).to include("broadcast 192.168.1.255")
      expect(cidr_output).to include("hosts    254")
      expect(cidr_output).to include("range    192.168.1.1 .. 192.168.1.254")
      expect(cidr_output).to include("u0xFFFEAC0A80100600")
      expect(cidr_output).to include("cidr     bits 11..6   24")
    end

    it "re-encodes decimal, rational, currency, and percentage immediates" do
      decimal_output = inspect_output("1.23")
      expect(decimal_output).to include("u0xFFFD000000003DFE")
      expect(decimal_output).to include("subtype  bits 47..46  0                  decimal")
      expect(decimal_output).to include("sig      bits 45..7   123                39-bit significand")
      expect(decimal_output).to include("scale    bits 6..0    -2                 decimal scale")

      rational_output = inspect_output("22/7")
      expect(rational_output).to include("u0xFFFE400005800007")
      expect(rational_output).to include("subtype  bits 47..45  2                  rational")

      currency_output = inspect_output("$5.25")
      expect(currency_output).to include("u0xFFFD4000000041BE")
      expect(currency_output).to include("subtype  bits 47..46  1                  currency")
      expect(currency_output).to include("symbol   bits 45..42  0                  $")

      percentage_output = inspect_output("15%")
      expect(percentage_output).to include("u0xFFFDFFC000000780")
      expect(percentage_output).to include("unit     bits 45..38  0xFF               percent sentinel")
    end

    it "explains UUID version, variant, and URN form" do
      output = inspect_output("550e8400-e29b-41d4-a716-446655440000")

      expect(output).to include("version  v4 random")
      expect(output).to include("variant  10xx RFC 4122 / RFC 9562")
      expect(output).to include("layout   8-4-4-4-12 hex nibbles")
      expect(output).to include("urn      urn:uuid:550e8400-e29b-41d4-a716-446655440000")
    end

    it "sketches small integer ranges" do
      output = inspect_output("1..5")

      expect(output).to include("shape    inclusive")
      expect(output).to include("size     5")
      expect(output).to include("diagram  1 ─ 2 ─ 3 ─ 4 ─ 5")
    end
  end

  describe "history cycling" do
    def build_line_editor(buffer = "")
      line_editor = Reline::LineEditor.new(Reline.core.config)
      line_editor.instance_variable_set(:@buffer_of_lines, [buffer])
      line_editor.instance_variable_set(:@line_index, 0)
      line_editor.instance_variable_set(:@byte_pointer, buffer.bytesize)
      line_editor
    end

    before do
      repl.send(:setup_readline)
      Reline::HISTORY.clear
      Reline::HISTORY << "!"
      Reline::HISTORY << "two"
      Reline::HISTORY << "!"
      Reline::HISTORY << "one"
    end

    after do
      Reline::HISTORY.clear
    end

    it "wraps up-arrow history navigation from the oldest entry back to the newest" do
      line_editor = build_line_editor

      line_editor.send(:ed_prev_history, nil)
      expect(Reline::HISTORY.to_a).to eq(["two", "one"])
      expect(line_editor.instance_variable_get(:@history_pointer)).to eq(1)
      expect(line_editor.instance_variable_get(:@buffer_of_lines)).to eq(["one"])

      line_editor.send(:ed_prev_history, nil)
      expect(line_editor.instance_variable_get(:@history_pointer)).to eq(0)
      expect(line_editor.instance_variable_get(:@buffer_of_lines)).to eq(["two"])

      line_editor.send(:ed_prev_history, nil)
      expect(line_editor.instance_variable_get(:@history_pointer)).to eq(1)
      expect(line_editor.instance_variable_get(:@buffer_of_lines)).to eq(["one"])
    end

    it "wraps down-arrow history navigation from the newest entry back to the oldest" do
      line_editor = build_line_editor

      line_editor.send(:ed_next_history, nil)
      expect(Reline::HISTORY.to_a).to eq(["two", "one"])
      expect(line_editor.instance_variable_get(:@history_pointer)).to eq(0)
      expect(line_editor.instance_variable_get(:@buffer_of_lines)).to eq(["two"])

      line_editor.send(:ed_next_history, nil)
      expect(line_editor.instance_variable_get(:@history_pointer)).to eq(1)
      expect(line_editor.instance_variable_get(:@buffer_of_lines)).to eq(["one"])

      line_editor.send(:ed_next_history, nil)
      expect(line_editor.instance_variable_get(:@history_pointer)).to eq(0)
      expect(line_editor.instance_variable_get(:@buffer_of_lines)).to eq(["two"])
    end
  end
end
