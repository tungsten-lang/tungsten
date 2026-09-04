# Tungsten Notes prototype (item 26)

`bin/tungsten notes` builds and launches the native macOS app from this
worktree. `bin/tungsten notes file.tnotes` opens a document. The generated app
lives in `build/apps/Tungsten Notes.app`; it is not installed over another app.
Set `TUNGSTEN_NOTES_APP` to launch an existing app bundle instead.
`--build-only` prints the bundle path and `--validate file.tnotes` runs the
prototype's document decoder without opening a window. Requires macOS 14+
and the Swift toolchain; no package download is needed.

No pre-existing Notes implementation was found in this checkout or the known
app/project locations, and the old command reported `File not found: notes`.
This starts the requested app as a SwiftUI document prototype. It displays
text, tables, line plots and explicit certificate records. It is not yet a
cell editor, notebook execution engine, debugger or live kernel connection.

## Hook recommendation

Start with **`#to_notes` returning structured data**, rather than HTML or
macOS views:

```w
use core/notes
+ Result
  -> new(@value)
  -> to_notes
    Notes.table(["result"], [[@value]])

Notes.write("result.tnotes", "My experiment", [Notes.render(Result.new(42))])
```

`Notes.render` calls `to_notes` when supported and otherwise produces a text
block. The method runs explicitly in the Tungsten producer process. The saved
file is inert data: opening it never executes Tungsten code or a verifier.
This keeps Core objects independent of SwiftUI and makes the same output usable
by other frontends. Add budget/context-aware rendering and a registry for
third-party classes later if actual applications need them.

Protocol v1 is JSON: `{schema_version: 1, title, blocks}`. Blocks are:

- `text`: `text` string;
- `table`: string `columns` and rectangular string `rows`;
- `line_plot`: finite numeric `[x,y]` pairs in `points`;
- `certificate`: `claim`, `level`, `verification: {status, verifier?}`,
  `assumptions`, optional `scope`.

The app validates versions, block kinds, table shapes, numeric finiteness and
size limits. Certificate level and replay status remain separate. Unknown
blocks are rejected, not rendered as executable content. Future image/mesh
blocks should reference artifacts by path, media type and hash; future live
updates should carry document/cell/revision IDs over a local message protocol.
They should not require a macOS-specific method on every scientific class.

`python3 scripts/test-notes.py` exercises an actual compiled W exporter and
the native decoder, including malformed documents. Build, validation and app
launch were checked; interactive editing and visual layout were not automated.
The app uses Apple's [DocumentGroup](https://developer.apple.com/documentation/swiftui/documentgroup)
and [FileDocument](https://developer.apple.com/documentation/swiftui/filedocument).
