describe Tungsten do
  around do |example|
    saved = ENV[Tungsten::LEXER_MODE_ENV]
    example.run
  ensure
    if saved
      ENV[Tungsten::LEXER_MODE_ENV] = saved
    else
      ENV.delete(Tungsten::LEXER_MODE_ENV)
    end
  end

  it "has a version" do
    expect(Tungsten::VERSION).not_to be nil
  end

  it "does something useful" do
    expect(true).to eq(true)
  end

  it "uses the codepoint lexer by default" do
    ENV.delete(Tungsten::LEXER_MODE_ENV)

    expect(Tungsten.lexer_mode).to eq("codepoint")
    expect(Tungsten.lexer_class).to eq(Tungsten::CodepointLexer)
  end

  it "uses the regex lexer when requested" do
    ENV[Tungsten::LEXER_MODE_ENV] = "regex"

    expect(Tungsten.lexer_mode).to eq("regex")
    expect(Tungsten.lexer_class).to eq(Tungsten::Lexer)
  end

  it "accepts reference as a legacy spelling for the regex lexer" do
    ENV[Tungsten::LEXER_MODE_ENV] = "reference"

    expect(Tungsten.lexer_mode).to eq("regex")
    expect(Tungsten.lexer_class).to eq(Tungsten::Lexer)
  end

  it "rejects unknown lexer modes" do
    ENV[Tungsten::LEXER_MODE_ENV] = "nope"

    expect { Tungsten.lexer_class }.to raise_error(ArgumentError, /expected codepoint or regex/)
  end
end
