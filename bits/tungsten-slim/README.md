# Tungsten Slim

A whitespace-significant template engine for Tungsten. Write clean, minimal templates that compile to HTML.

## Installation

Add to your `Bitfile`:

```
dependency "tungsten-slim", "~> 0.1"
```

## Syntax

### Tags

HTML elements are written by tag name. Nesting is controlled by indentation (2 spaces).

```slim
div
  h1 "Hello, world"
  p "Welcome to Slim"
```

### IDs and Classes

Use `#` for IDs and `.` for classes, just like CSS selectors:

```slim
div#header.main-nav
  ul.nav-links
    li.active
      a(href="/") "Home"
```

### Attributes

Wrap attributes in parentheses:

```slim
a(href="/bits" class="nav-link" target="_blank") "Browse Bits"
input(type="email" name="user[email]" required)
```

### Text Content

Place quoted text after a tag to set its text content:

```slim
h1 "Welcome to Tungsten"
p "Hello, [user.name]"
```

### Interpolation

Tungsten's bracket syntax `[expression]` is used for interpolation inside strings:

```slim
title "[page_title] — Tungsten"
p "You have [bits.count] bits published"
```

### Code Lines

Use `-` for code that produces no output, `=` for output expressions:

```slim
- if @signed_in?
  p "Welcome back!"
- else
  a(href="/sign_in") "Sign In"

= @bit.description
```

### Comments

Use `/` for HTML comments:

```slim
/ This is an HTML comment
div "Visible content"
```

### Doctype

```slim
doctype html
```

### Literal Text

Use `|` for literal text blocks:

```slim
p
  | This is a long block of text
  | that spans multiple lines.
```

## Integration with Carbide

Slim integrates automatically with Tungsten Carbide. Name your templates with the `.slim` extension:

```
lib/views/layouts/application.slim
lib/views/bits/index.slim
lib/views/bits/show.slim
```

## License

MIT — see [LICENSE](LICENSE).
