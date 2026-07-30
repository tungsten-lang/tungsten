# frozen_string_literal: true

# Source families whose contents can affect a self-hosted compiler stage.
# The compiler lexer imports languages/tungsten/lexers/regex_helpers.w, while
# core classes can be loaded both explicitly and through the autoload registry.
module TungstenBuildCacheInputs
  module_function

  def compiler_source_paths(compiler_dir_name)
    [
      File.join(compiler_dir_name, "tungsten.w"),
      File.join(compiler_dir_name, "lib"),
      "core",
      File.join("languages", "tungsten", "lexers")
    ]
  end
end
