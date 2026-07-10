# 04 — Literals & units

Currency, percentages, physical units, unicode math, and date/time literals.
These are first-class surface forms — not libraries you import for demo day.

← [03 — OOP](03-oop.md) · [Index](README.md) · Next: [05 — Novelties](05-novelties.md) →

---

## Currency and percentages

Money literals use currency symbols; percent is a postfix `%` (and related
unicode percent signs).

```tungsten
price = $499.99

<< price - 15%               # => ≈$424.99
<< price - 15% + 8.25%       # => ≈$460.05

<< $3.50 - 25¢               # => $3.25
<< 20% - 15%                 # => 5%
```

```bash
bin/tungsten -e '<< $3.50 - 25¢'
bin/tungsten -e '<< $499.99 - 15%'
```

A small shopping-cart style example:

```tungsten
items = [
  {name: "hamburger", price: $5.50, quantity: 4},
  {name: "milkshake", price: $2.86, quantity: 2}
]

subtotal = $0.00
items.each ->(item)
  cost = item[:price] * item[:quantity]
  << "[item[:name]]: [item[:quantity]] x [item[:price]] = [cost]"
  subtotal += cost

tax = subtotal * 0.0765
<< "Subtotal: [subtotal]"
<< "Tax:      [tax]"
<< "Total:    [subtotal + tax]"
```

```bash
bin/tungsten doc/examples/rosetta_code/currency.w
```

Because amounts ride on exact decimals (and dedicated currency tags in the
runtime value encoding), you avoid the classic `0.1 + 0.2` float traps for
money-shaped work.

---

## Units of measurement

A number followed by a unit becomes a **Quantity**. Compatible units add;
incompatible dimensions error.

```tungsten
c = 299_792_458 m/s
m = 1 kg

<< e = m·c²                  # energy-ish expression with unicode operators

<< 3 ft + 12 in              # => 4 ft
<< 10 ft * 10 ft             # => 100 ft²
<< 1 cm * 1 cm * 1 cm        # => 1 cm³

# Dimension mismatch is an error:
# << 2 m + 2 lbs
```

### Conversion with pipe (`|`) or `»`

```tungsten
c = 299_792_458 m/s

<< 1 acre | sqft             # => 43560 sqft
<< 6 ft + 2 in | cm(2)       # => 187.96 cm   (2) = round to 2 decimals
<< 5 kg + 3 kg | lb(2)       # => 17.64 lb

<< c * 1 ns | cm(2)          # light-travel in one nanosecond ≈ 29.98 cm
<< 1 g · c² | J              # rest energy of 1 g

<< "Light travels [c * 1 s | km] in one second"
<< "A marathon is [42195 m | mi(1)]"
```

> **Note:** unit conversion on the **compiled** path is still evolving
> (preview). Prefer trying unit snippets with quick run / `-e` first; if a
> conversion fails under `-o`, check release notes and the units appendix.

SI base units, many derived units, binary information units (`KiB`, `Mbps`),
and time scales from `ns` to `fortnight` are listed in
[appendix_units_of_measurement.md](../specification/appendix_units_of_measurement.md).

---

## Exact decimals vs floats

```tungsten
<< 0.1 + 0.2 == 0.3          # => true   (Decimal)

f = ~0.1 + ~0.2              # machine floats
<< f                         # classic float noise possible
```

| Literal | Type | When to use |
| ------- | ---- | ----------- |
| `3.14` | Decimal | Default — money-adjacent, exact fractions |
| `~3.14` | Float | Numerics, SIMD/GPU, performance-sensitive FP |
| `$3.14` | Currency | Money |
| `3.14%` / `15%` | Percent | Relative change |

---

## Unicode math in source

Tungsten source is UTF-8. Common math glyphs are real operators / sugar:

```tungsten
+ Point
  -> new(@x, @y, @z) ro

  -> distance/1
    √(Δx² + Δy² + Δz²)

<< Point(3, 4, 0).distance(Point(0, 0, 0))   # => 5
```

Also seen in the language surface:

| Glyph / form | Role |
| ------------ | ---- |
| `√` | Square root |
| `²` `⁷` … | Superscript powers |
| `·` | Multiplication (dot) |
| `Δx` / prime `x'` | Deltas / "other" field in binary methods |
| `Σ(...)` | Summation sugar |
| `∫(...)` | Numerical integral; REPL can plot |

```tungsten
# Pipeline / sum sketches (see man page / REPL for full forms)
# Σ(2x⁷ + 3x², 1..10)
# ∫(x², 0..2)
```

In the REPL, `? ∫(x², 0..2)` can plot the curve (braille terminal plot).

You can always write ASCII equivalents (`.sqrt`, `** 2`, `*`) when glyphs are
inconvenient.

---

## Dates, times, durations

These are real lexical forms (see the language spec §2.10):

```tungsten
# Calendar date
d = 2024-01-15

# Year-month only
m = 2024-01

# DateTime
t = 2024-01-15T14:30:00Z

# Clock / duration style literals appear as Duration / related types
# e.g. 5m30s in engines that accept duration surface forms
```

Rules of thumb:

- `YYYY-MM-DD` with **no spaces** around hyphens is a date; spaces make it
  subtraction (`2024 - 01 - 15`).
- Runtime types include `Date`, `Month`, `Instant` (unix ms), and `Duration`
  (see [WVALUE.md](../WVALUE.md) and `core/date.w` / `core/duration.w`).
- Interpreter and compiler differ slightly on range-checking of date fields;
  the interpreter is stricter about invalid calendar components.

---

## Other packed literals (awareness)

Useful when reading code or the value encoding docs:

| Literal | Example | Type-ish |
| ------- | ------- | -------- |
| Color | `#FF0000`, `#F00` | Color (3/4/6/8 hex digits after `#`) |
| Byte array | `« ff 00 a5 »` | ByteArray |
| IPv4 | `192.168.1.1`, `10.0.0.1:8080` | IPv4 |
| CIDR | `10.0.0.0/8` | network prefix |
| Word array | `%w[red green blue]` | `["red", "green", "blue"]` |
| Symbol array | `%i[get post put]` | `[:get, :post, :put]` |

`#` starts a comment unless it is exactly a 3/4/6/8-digit hex color run.

---

## How this maps to the runtime (optional)

Values are NaN-boxed 64-bit words (WValues). Currency and quantity share a
numeric tag space; dates/instants/durations have their own tags. You do not
need this to write application code; it explains why small ints are free,
bignums heap-allocate, and "weird" literals are still single values.

See [WVALUE.md](../WVALUE.md) for the bit layouts.

---

## Try it

```bash
bin/tungsten -e '<< $10.00 - 15%'
bin/tungsten -e '<< 3 ft + 12 in'
bin/tungsten doc/examples/rosetta_code/currency.w
```

Next: **[05 — Novelties](05-novelties.md)**
