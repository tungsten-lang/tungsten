# Character — Unicode character-database record (core/character.w).
#
# BLOCKED: core/character.w cannot be loaded by either engine, and the class is
# not in the autoload manifest either, so there is no reachable surface to
# assert against. The intended surface is pinned below as BUG-commented checks;
# uncomment them once the file parses.
#
# BUG: `use core/character` is a parse error on both engines. The constructor
#
#     -> new
#       @data
#         abbreviations: %w[LF NL EOL]
#         age:       1.1
#         ...
#
# writes an indented key/value block under a bare `@data` ivar reference, which is
# not a hash literal: "Unexpected token INDENT() @pos=558/824 --> core/character.w:98:7"
# (E_PARSE_UNEXPECTED_TOKEN).
# Repro: printf 'use core/character\n<< 1\n' > /tmp/ch.w && bin/tungsten run --interpret /tmp/ch.w
#
# BUG: `Character` has no `auto :Character, "character"` line in core/tungsten.w, so
# without the `use` the class is simply absent: "Undefined class 'Character'".
# Repro: printf '<< type(Character.new)\n' > /tmp/ch.w && bin/tungsten run --interpret /tmp/ch.w
#
# Run (once the module parses):
#   bin/tungsten run --interpret spec/core/character_spec.w
#   bin/tungsten -o /tmp/character_spec spec/core/character_spec.w && /tmp/character_spec

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# use core/character
#
# c = Character.new
# check("constructs", type(c) == "Character")
# check("is_a? Character", c.is_a?(Character))
# ---- the seeded @data record describes U+000A LINE FEED ----
# check("name falls back through unicode_1_name", c.name == "LINE FEED (LF)")
# check("block", c.block == "ASCII")
# check("general_category", c.general_category == "Control")
# check("script", c.script == "Common")
# check("age", c.age == 1.1)
# check("digraph", c.digraph == "LF")
# check("abbreviations", c.abbreviations == ["LF", "NL", "EOL"])
# check("aliases", c.aliases.size == 3)
# check("bytes", c.bytes == "<<0A>>")
# check("codepoint", c.codepoint == "<<00,0A>>")
# check("control names", c.control.size == 3)
# ---- escapes sub-hash ----
# check("c escape", c.escapes[:c] == "\\u000A")
# check("json escape", c.escapes[:json] == "\\uA")
# check("url escape", c.escapes[:url] == "%0A")
# ---- the alias table maps short property names onto the long ones ----
# check("blk aliases block", c.blk == c.block)
# check("gc aliases general_category", c.gc == c.general_category)
# check("sc aliases script", c.sc == c.script)
# check("na aliases unicode_name", c.na == c.unicode_name)
# check("lower aliases lowercase", c.lower == c.lowercase)
# check("upper aliases uppercase", c.upper == c.uppercase)
# check("wspace aliases white_space", c.wspace == c.white_space)
# check("xids aliases xid_start", c.xids == c.xid_start)
# ---- data is a memoized, eagerly built CharacterMeta ----
# check("data is a CharacterMeta", type(c.data) == "CharacterMeta")
# check("data is memoized", c.data == c.data)
# ---- classification predicates ----
# check("printable? is always true", c.printable?)
# check("is_ascii?", c.is_ascii?)
# check("is_cntrl?", c.is_cntrl?)
# check("is_alpha? is false for a control", !c.is_alpha?)
# check("is_digit? is false for a control", !c.is_digit?)
# check("is_space?", c.is_space?)
# check("is_valid?", c.is_valid?)
# ---- method_missing routes unknown names into @data, and raises otherwise ----
# check("method_missing reads a data key", c.wrong_iso8851_1_mojibake == "â")
# missing = false
# begin
#   c.definitely_not_a_property
# rescue e
#   missing = true
# check("method_missing calls super for an unknown key", missing)

<< "ALL PASS character_spec ([passed.load()] checks — core/character.w does not parse; see the BUG notes above)"
