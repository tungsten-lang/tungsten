module Tungsten::AST
  class Fn < Def
    def ast_fingerprint(name_map = {})
      parts = [self.class.name]
      # Args: positional structure only (types/defaults), not names
      (args || []).each_with_index do |arg, i|
        parts << "arg_#{i}"
        parts << arg.default.ast_fingerprint(name_map) if arg.default
        parts << arg.restriction.inspect if arg.restriction
      end
      # Body: structural content with name_map applied
      parts << body.ast_fingerprint(name_map)
      parts.join("|")
    end
  end
end
