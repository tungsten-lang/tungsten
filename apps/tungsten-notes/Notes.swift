import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Charts

extension UTType {
    static let tungstenNote = UTType(exportedAs: "org.tungstenlang.notes.document", conformingTo: .json)
}

struct Verification: Codable { var status: String; var verifier: String? }
struct NoteBlock: Codable {
    var kind: String
    var text: String?
    var columns: [String]?
    var rows: [[String]]?
    var points: [[Double]]?
    var claim: String?
    var scope: String?
    var level: String?
    var verification: Verification?
    var assumptions: [String]?
}
struct Note: Codable {
    var schema_version: Int
    var title: String
    var blocks: [NoteBlock]
    func validate() throws {
        func fail(_ text: String) throws { throw NSError(domain: "Tungsten Notes", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
        guard schema_version == 1 else { try fail("Unsupported Notes schema version"); return }
        guard blocks.count <= 1000 else { try fail("Too many blocks"); return }
        for block in blocks {
            switch block.kind {
            case "text":
                if block.text == nil { try fail("Text block needs text") }
            case "table":
                guard let columns = block.columns, let rows = block.rows,
                      !columns.isEmpty, columns.count <= 100, rows.count <= 10000,
                      rows.allSatisfy({ $0.count == columns.count }) else {
                    try fail("Table needs matching columns and rows"); return
                }
            case "line_plot":
                guard let points = block.points, !points.isEmpty, points.count <= 100000,
                      points.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isFinite) }) else {
                    try fail("Plot needs finite [x, y] points"); return
                }
            case "certificate":
                let levels = ["finite_checked", "arithmetic_checked", "trusted_theorem_import", "kernel_checked", "conditional", "heuristic"]
                guard block.claim != nil, let level = block.level, levels.contains(level),
                      let verification = block.verification,
                      ["passed", "failed", "unknown", "not_run"].contains(verification.status),
                      block.assumptions != nil else {
                    try fail("Certificate needs a claim, known level, replay status and assumptions"); return
                }
            default: try fail("Unsupported block kind: \(block.kind)")
            }
        }
    }
    static func read(_ data: Data) throws -> Note {
        guard data.count <= 16 * 1024 * 1024 else {
            throw NSError(domain: "Tungsten Notes", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document exceeds 16 MiB"])
        }
        let note = try JSONDecoder().decode(Note.self, from: data)
        try note.validate()
        return note
    }
}
struct NotesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.tungstenNote] }
    var note: Note
    init() { note = Note(schema_version: 1, title: "Untitled experiment", blocks: [NoteBlock(kind: "text", text: "Export a .tnotes document from Tungsten to begin.")]) }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        note = try Note.read(data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try note.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(note))
    }
}
struct NotesView: View {
    let note: Note
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("TUNGSTEN NOTES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(note.title).font(.largeTitle.weight(.bold))
                Text("Saved results · structured, inspectable documents").foregroundStyle(.secondary)
                ForEach(Array(note.blocks.enumerated()), id: \.offset) { _, block in
                    BlockView(block: block)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
                }
            }.padding(32).frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
        }.background(Color(nsColor: .windowBackgroundColor))
            .frame(minWidth: 640, minHeight: 480)
    }
}
struct BlockView: View {
    let block: NoteBlock
    var body: some View {
        switch block.kind {
        case "text": Text(block.text ?? "").textSelection(.enabled)
        case "table":
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    GridRow {
                        ForEach(Array((block.columns ?? []).enumerated()), id: \.offset) { _, label in
                            Text(label).fontWeight(.semibold)
                        }
                    }
                    Divider()
                    ForEach(Array((block.rows ?? []).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell).monospacedDigit().textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        case "line_plot":
            Chart(Array((block.points ?? []).enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("x", point[0]), y: .value("y", point[1])).foregroundStyle(.cyan)
            }.chartXAxisLabel("x").chartYAxisLabel("y").frame(height: 280)
        case "certificate":
            VStack(alignment: .leading, spacing: 10) {
                Text(block.claim ?? "").font(.headline)
                Text("Level: \(block.level ?? "unknown") · Replay: \(block.verification?.status ?? "unknown")")
                    .font(.subheadline.monospaced()).foregroundStyle(.secondary)
                if let scope = block.scope { Text(scope).textSelection(.enabled) }
                if let verifier = block.verification?.verifier { Text("Verifier: \(verifier)") }
                ForEach(block.assumptions ?? [], id: \.self) { Text("Assumption: \($0)").foregroundStyle(.orange) }
                Text("This view reports saved evidence. Opening a document does not run a verifier.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        default: Text("Unsupported block")
        }
    }
}
struct NotesApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: NotesDocument()) { file in
            NotesView(note: file.document.note)
        }.defaultSize(width: 900, height: 720)
    }
}
@main enum Main {
    static func main() {
        let args = CommandLine.arguments
        if args.count == 3 && args[1] == "--validate" {
            do {
                let note = try Note.read(Data(contentsOf: URL(fileURLWithPath: args[2])))
                print("Valid Notes v1: \(note.title) (\(note.blocks.count) blocks)")
            } catch {
                fputs("\(error.localizedDescription)\n", stderr); exit(1)
            }
        } else { NotesApp.main() }
    }
}
