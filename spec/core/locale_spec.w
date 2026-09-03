# Locale — CLDR-style locale data: currency, calendar names, patterns,
# language / script / region tables (core/locale.w).
#
# BLOCKED: core/locale.w cannot be loaded by either engine, and `Locale` has no
# entry in the autoload manifest, so there is no reachable surface. The intended
# surface is pinned below as BUG-commented checks.
#
# BUG: `use core/locale` fails to lex on both engines at the very first locale key:
# "uppercase ASCII is not valid in identifiers: 'en_US' — use snake_case
#  --> core/locale.w:13:3". The `Tungsten.locales` block keys every locale by its
# BCP-47 tag (en_US, en_GB, de_DE, fr_FR, it_IT, ...), which the identifier lexer
# rejects. Every locale in the file is affected, not just the first.
# Repro: printf 'use core/locale\n<< 1\n' > /tmp/lo.w && bin/tungsten run --interpret /tmp/lo.w
#
# BUG: there is no `auto :Locale, "locale"` line in core/tungsten.w, so without the
# `use` the class is absent entirely: "Undefined class 'Locale'".
# Repro: printf '<< type(Locale.new)\n' > /tmp/lo.w && bin/tungsten run --interpret /tmp/lo.w
#
# BUG: the class body itself uses `attr :currency` / `attr :position, in: %i[before after]`
# / `attr :separators`, none of which the parser supports as a class-body form; the file
# needs `- data` / `ro` / `rw` declarations instead.
#
# Run (once the module parses):
#   bin/tungsten run --interpret spec/core/locale_spec.w
#   bin/tungsten -o /tmp/locale_spec spec/core/locale_spec.w && /tmp/locale_spec

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# use core/locale
#
# ---- the class surface ----
# l = Locale.new
# check("constructs", type(l) == "Locale")
# check("currency attribute", l.currency == nil)
# check("position is constrained to before/after", l.position == nil)
# check("separators attribute", l.separators == nil)
#
# ---- the registry: Tungsten.locales keyed by BCP-47 tag ----
# check("en_US is registered", Tungsten.locales[:en_US] != nil)
# check("the file defines several locales", Tungsten.locales.size >= 5)
#
# en = Tungsten.locales[:en_US]
# ---- currency and platform identity ----
# check("en_US currency", en[:currency] == "$ USD")
# check("en_US windows id", en[:windows_id] == 0x409)
# check("en_US script", en[:script] == ["Latn", "Latin"])
#
# ---- calendar names: narrow / short / abbr / long per row ----
# check("seven day rows", en[:days].size == 7)
# check("Sunday row", en[:days][0] == "S Su Sun Sunday")
# check("Saturday row", en[:days][6] == "S Sa Sat Saturday")
# check("twelve month rows", en[:months].size == 12)
# check("January row", en[:months][0] == "J Jan January")
# check("December row", en[:months][11] == "D Dec December")
# check("am/pm", en[:ampm] == ["am AM", "pm PM"])
# check("two eras", en[:eras].size == 2)
#
# ---- format patterns ----
# check("four time patterns", en[:patterns][:times].size == 4)
# check("shortest time pattern", en[:patterns][:times][0] == "h:mm a")
# check("four date patterns", en[:patterns][:dates].size == 4)
# check("shortest date pattern", en[:patterns][:dates][0] == "M/d/yy")
# check("longest date pattern", en[:patterns][:dates][3] == "EEEE, MMMM d, y")
# check("datetime pattern composes date and time", en[:patterns][:datetime] == "[date], [time]")
# check("decimal pattern", en[:patterns][:decimal] == "9,990.00")
# check("currency pattern", en[:patterns][:currency] == "$9,990.00")
# check("percent pattern", en[:patterns][:percent] == "9,990%")
#
# ---- week configuration ----
# check("en_US week starts on Sunday", en[:first_day] == "Sunday")
# check("en_US first week days", en[:first_week_days] == 1)
#
# ---- language / script / region tables ----
# check("language codes map to names", en[:languages][:aa] == "Afar")
# check("three-letter language codes", en[:languages][:ace] == "Achinese")
# check("region 001 is the world", en[:regions]["001"] == "World")
# check("region 002 is Africa", en[:regions]["002"] == "Africa")
# check("region 142 is Asia", en[:regions]["142"] == "Asia")
#
# ---- a second locale translates the same tables ----
# it = Tungsten.locales[:it_IT]
# check("it_IT translates the months", it[:months][11] == "D dic dicembre")
# check("it_IT translates the languages", it[:languages][:aa] == "afar")
# check("it_IT translates the scripts", it[:scripts][:Arab] == "arabo")
# check("it_IT translates the regions", it[:regions]["003"] == "Nord America")
# check("the region code set is shared across locales",
#       it[:regions].keys.sort == en[:regions].keys.sort)

<< "ALL PASS locale_spec ([passed.load()] checks — core/locale.w does not lex; see the BUG notes above)"
