import CoreML
import Foundation

private let batchSize = 64
private let featureCount = 16
private let featureSchema = "metaflip-ranker-v1"
private let featureNames = [
  "rank", "rank_debt", "total_bits", "bits_per_term", "flip_pairs",
  "flip_pairs_per_term", "c3_symmetric", "unique_u", "unique_v", "unique_w",
  "singleton_u", "singleton_v", "singleton_w", "max_bucket_u", "max_bucket_v",
  "max_bucket_w",
]

private enum RankerError: Error, CustomStringConvertible {
  case usage(String)
  case invalid(String)

  var description: String {
    switch self {
    case .usage(let message), .invalid(let message): return message
    }
  }
}

private enum ComputeMode: String, Encodable {
  case cpuAndNeuralEngine
  case cpuOnly

  var units: MLComputeUnits {
    switch self {
    case .cpuAndNeuralEngine: return .cpuAndNeuralEngine
    case .cpuOnly: return .cpuOnly
    }
  }
}

private struct Options {
  var modelPath = ""
  var requestPath: String?
  var responsePath: String?
  var stopPath: String?
  var inputName = "features"
  var outputName = "scores"
  var parentPID = getppid()
  var workers = 1
  var pollMicroseconds: UInt32 = 1_000
  var computeMode = ComputeMode.cpuAndNeuralEngine
  var requireANE = true

  static let help = """
  Usage:
    coreml_ranker --model MODEL --serve REQUEST RESPONSE [options]
    coreml_ranker --model MODEL --jsonl [options]

  Options:
    --compute cpuAndNeuralEngine|cpuOnly  Default: cpuAndNeuralEngine
    --workers 1|2|4                      Host preprocessing workers
    --input-name NAME                    Default: features
    --output-name NAME                   Default: scores
    --stop-file PATH                     Default: REQUEST.stop
    --parent-pid PID                     Exit if this process is no longer present
    --poll-us N                          Mailbox poll interval (default: 1000)
    --allow-cpu-fallback                 Report, rather than reject, no ANE placement

  The model contract is Float32 features[64,16] -> scores[64,1]. Mailbox input is
  `epoch<TAB>EPOCH<TAB>N` followed by N rows of 16 tab-separated finite numbers.
  Output has the same header followed by `row<TAB>score`; replacement is atomic.
  JSONL accepts {"op":"score","id":"...","rows":[[16 numbers], ...]}.
  """

  static func parse(_ arguments: [String]) throws -> Options {
    var result = Options()
    var sawJSONL = false
    var i = 0
    func value(after option: String) throws -> String {
      guard i + 1 < arguments.count else {
        throw RankerError.usage("missing value after \(option)\n\(help)")
      }
      i += 1
      return arguments[i]
    }

    while i < arguments.count {
      let option = arguments[i]
      switch option {
      case "--model":
        result.modelPath = try value(after: option)
      case "--serve":
        result.requestPath = try value(after: option)
        result.responsePath = try value(after: option)
      case "--jsonl":
        sawJSONL = true
      case "--compute":
        let raw = try value(after: option)
        switch raw {
        case "cpuAndNeuralEngine", "cpu-ne":
          result.computeMode = .cpuAndNeuralEngine
          result.requireANE = true
        case "cpuOnly", "cpu":
          result.computeMode = .cpuOnly
          result.requireANE = false
        default:
          throw RankerError.usage("invalid --compute value \(raw)\n\(help)")
        }
      case "--workers":
        let raw = try value(after: option)
        guard let workers = Int(raw), [1, 2, 4].contains(workers) else {
          throw RankerError.usage("--workers must be 1, 2, or 4\n\(help)")
        }
        result.workers = workers
      case "--input-name":
        result.inputName = try value(after: option)
      case "--output-name":
        result.outputName = try value(after: option)
      case "--stop-file":
        result.stopPath = try value(after: option)
      case "--parent-pid":
        let raw = try value(after: option)
        guard let pid = Int32(raw), pid > 0 else {
          throw RankerError.usage("--parent-pid must be a positive process id\n\(help)")
        }
        result.parentPID = pid
      case "--poll-us":
        let raw = try value(after: option)
        guard let delay = UInt32(raw), delay > 0 else {
          throw RankerError.usage("--poll-us must be a positive UInt32\n\(help)")
        }
        result.pollMicroseconds = delay
      case "--allow-cpu-fallback", "--allow-no-ane":
        result.requireANE = false
      case "--help", "-h":
        print(help)
        Foundation.exit(EXIT_SUCCESS)
      default:
        throw RankerError.usage("unknown option \(option)\n\(help)")
      }
      i += 1
    }

    guard !result.modelPath.isEmpty else {
      throw RankerError.usage("--model is required\n\(help)")
    }
    let mailbox = result.requestPath != nil || result.responsePath != nil
    guard mailbox != sawJSONL else {
      throw RankerError.usage("choose exactly one of --serve or --jsonl\n\(help)")
    }
    if mailbox && result.stopPath == nil {
      result.stopPath = result.requestPath! + ".stop"
    }
    return result
  }
}

private struct PlacementSummary: Encodable {
  var modelKind = "unsupported"
  var inspectedUnits = 0
  var unavailableUsage = 0
  var preferredCPU = 0
  var preferredGPU = 0
  var preferredNeuralEngine = 0
  var supportedCPU = 0
  var supportedGPU = 0
  var supportedNeuralEngine = 0
  var neuralEngineAvailable = false
  var availableDevices: [String] = []
  var preferredCPUKinds: [String] = []
  var preferredGPUKinds: [String] = []
  var preferredNeuralEngineKinds: [String] = []

  var aneVerified: Bool {
    preferredNeuralEngine > 0 && preferredGPU == 0
  }
}

private func add(
  _ usage: MLComputePlan.DeviceUsage?,
  kind: String,
  to summary: inout PlacementSummary
) {
  summary.inspectedUnits += 1
  guard let usage else {
    summary.unavailableUsage += 1
    return
  }
  switch usage.preferred {
  case .cpu:
    summary.preferredCPU += 1
    summary.preferredCPUKinds.append(kind)
  case .gpu:
    summary.preferredGPU += 1
    summary.preferredGPUKinds.append(kind)
  case .neuralEngine:
    summary.preferredNeuralEngine += 1
    summary.preferredNeuralEngineKinds.append(kind)
  @unknown default: break
  }
  for device in usage.supported {
    switch device {
    case .cpu: summary.supportedCPU += 1
    case .gpu: summary.supportedGPU += 1
    case .neuralEngine: summary.supportedNeuralEngine += 1
    @unknown default: break
    }
  }
}

@available(macOS 14.4, *)
private func summarize(_ plan: MLComputePlan) -> PlacementSummary {
  var summary = PlacementSummary()
  summary.availableDevices = MLModel.availableComputeDevices.map(\.description)
  summary.neuralEngineAvailable = MLModel.availableComputeDevices.contains {
    if case .neuralEngine = $0 { return true }
    return false
  }

  func visitBlock(_ block: MLModelStructure.Program.Block) {
    for operation in block.operations {
      add(plan.deviceUsage(for: operation), kind: operation.operatorName, to: &summary)
      for child in operation.blocks { visitBlock(child) }
    }
  }

  func visit(_ structure: MLModelStructure) {
    switch structure {
    case .neuralNetwork(let network):
      if summary.modelKind == "unsupported" { summary.modelKind = "neuralNetwork" }
      for layer in network.layers {
        add(plan.deviceUsage(for: layer), kind: layer.type, to: &summary)
      }
    case .program(let program):
      if summary.modelKind == "unsupported" { summary.modelKind = "program" }
      for function in program.functions.values { visitBlock(function.block) }
    case .pipeline(let pipeline):
      summary.modelKind = "pipeline"
      for model in pipeline.subModels { visit(model) }
    case .unsupported:
      break
    @unknown default:
      break
    }
  }

  visit(plan.modelStructure)
  return summary
}

private struct ReadyEvent: Encodable {
  let event = "ready"
  let pid: Int32
  let parentPID: Int32
  let compute: ComputeMode
  let preprocessWorkers: Int
  let batchSize: Int
  let featureCount: Int
  let inputName: String
  let outputName: String
  let featureSchema: String
  let featureNames: [String]
  let compiledModel: String
  let placementEvidence = "MLComputePlan preferred-device map"
  let anePlacementVerified: Bool
  let placement: PlacementSummary
}

private struct BatchEvent: Encodable {
  let event = "batch"
  let epoch: UInt64?
  let id: String?
  let rows: Int
  let completedBatches: UInt64
  let preprocessNs: UInt64
  let predictionNs: UInt64
  let totalNs: UInt64
}

private struct ErrorEvent: Encodable {
  let event = "error"
  let message: String
}

private final class EventWriter: @unchecked Sendable {
  private let lock = NSLock()
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  func stderr<T: Encodable>(_ value: T) {
    lock.lock()
    defer { lock.unlock() }
    guard let data = try? encoder.encode(value) else { return }
    FileHandle.standardError.write(data)
    FileHandle.standardError.write(Data([0x0a]))
  }

  func stdout<T: Encodable>(_ value: T) {
    lock.lock()
    defer { lock.unlock() }
    guard let data = try? encoder.encode(value) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0a]))
  }
}

private final class ParsedRows: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [[Float]?]
  private var firstError: String?

  init(count: Int) { storage = Array(repeating: nil, count: count) }

  func put(_ row: [Float], at index: Int) {
    lock.lock()
    storage[index] = row
    lock.unlock()
  }

  func fail(_ message: String) {
    lock.lock()
    if firstError == nil { firstError = message }
    lock.unlock()
  }

  func finish() throws -> [[Float]] {
    lock.lock()
    defer { lock.unlock() }
    if let firstError { throw RankerError.invalid(firstError) }
    guard storage.allSatisfy({ $0 != nil }) else {
      throw RankerError.invalid("internal preprocessing error")
    }
    return storage.map { $0! }
  }
}

private func parseRows(_ lines: ArraySlice<Substring>, expected: Int, workers: Int) throws -> [[Float]] {
  guard expected > 0 && expected <= batchSize else {
    throw RankerError.invalid("row count must be in 1...\(batchSize)")
  }
  guard lines.count == expected else {
    throw RankerError.invalid("declared \(expected) rows but found \(lines.count)")
  }
  let source = lines.map(String.init)
  let parsed = ParsedRows(count: expected)
  let workerCount = min(workers, expected)
  DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
    var rowIndex = worker
    while rowIndex < expected {
      let fields = source[rowIndex].split(separator: "\t", omittingEmptySubsequences: false)
      if fields.count != featureCount {
        parsed.fail("row \(rowIndex) has \(fields.count) features, expected \(featureCount)")
      } else {
        var row: [Float] = []
        row.reserveCapacity(featureCount)
        for field in fields {
          guard let value = Float(field), value.isFinite else {
            parsed.fail("row \(rowIndex) contains a non-finite or invalid feature")
            row.removeAll()
            break
          }
          row.append(value)
        }
        if row.count == featureCount { parsed.put(row, at: rowIndex) }
      }
      rowIndex += workerCount
    }
  }
  return try parsed.finish()
}

private func makeInput(_ rows: [[Float]]) throws -> MLMultiArray {
  guard !rows.isEmpty && rows.count <= batchSize else {
    throw RankerError.invalid("row count must be in 1...\(batchSize)")
  }
  for (index, row) in rows.enumerated() {
    guard row.count == featureCount, row.allSatisfy(\.isFinite) else {
      throw RankerError.invalid("row \(index) must contain \(featureCount) finite features")
    }
  }
  let input = try MLMultiArray(
    shape: [NSNumber(value: batchSize), NSNumber(value: featureCount)],
    dataType: .float32
  )
  input.withUnsafeMutableBytes { raw, strides in
    let values = raw.bindMemory(to: Float.self)
    for i in 0..<values.count { values[i] = 0 }
    for row in 0..<rows.count {
      for column in 0..<featureCount {
        values[row * strides[0] + column * strides[1]] = rows[row][column]
      }
    }
  }
  return input
}

private final class Ranker: @unchecked Sendable {
  private let model: MLModel
  private let inputName: String
  private let outputName: String

  init(model: MLModel, inputName: String, outputName: String) throws {
    self.model = model
    self.inputName = inputName
    self.outputName = outputName
    try Self.checkModel(model, inputName: inputName, outputName: outputName)
  }

  private static func checkModel(_ model: MLModel, inputName: String, outputName: String) throws {
    guard let input = model.modelDescription.inputDescriptionsByName[inputName],
          let inputConstraint = input.multiArrayConstraint else {
      throw RankerError.invalid("model has no multi-array input named \(inputName)")
    }
    guard inputConstraint.shape.map(\.intValue) == [batchSize, featureCount],
          inputConstraint.dataType == .float32 else {
      throw RankerError.invalid("model input \(inputName) must be Float32[64,16]")
    }
    guard let output = model.modelDescription.outputDescriptionsByName[outputName],
          let outputConstraint = output.multiArrayConstraint else {
      throw RankerError.invalid("model has no multi-array output named \(outputName)")
    }
    guard outputConstraint.shape.map(\.intValue) == [batchSize, 1],
          outputConstraint.dataType == .float32 else {
      throw RankerError.invalid("model output \(outputName) must be Float32[64,1]")
    }
    guard let metadata = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String],
          metadata["feature_schema"] == featureSchema,
          let encodedNames = metadata["feature_names"],
          let names = try? JSONDecoder().decode([String].self, from: Data(encodedNames.utf8)),
          names == featureNames else {
      throw RankerError.invalid("model metadata does not match \(featureSchema)")
    }
  }

  func predict(_ input: MLMultiArray, rowCount: Int) async throws -> [Float] {
    let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: input])
    let result = try await model.prediction(from: provider)
    guard let output = result.featureValue(for: outputName)?.multiArrayValue else {
      throw RankerError.invalid("prediction omitted multi-array output \(outputName)")
    }
    guard output.shape.map(\.intValue) == [batchSize, 1], output.dataType == .float32 else {
      throw RankerError.invalid("prediction output changed shape or data type")
    }
    return try output.withUnsafeBytes { raw in
      let values = raw.bindMemory(to: Float.self)
      let strides = output.strides.map(\.intValue)
      let scores = (0..<rowCount).map { values[$0 * strides[0]] }
      guard scores.allSatisfy(\.isFinite) else {
        throw RankerError.invalid("prediction returned a non-finite score")
      }
      return scores
    }
  }
}

private struct MailboxRequest {
  let epoch: UInt64
  let rows: [[Float]]
}

private struct MailboxStamp: Equatable {
  let modified: Date
  let size: UInt64
  let inode: UInt64
}

private func mailboxStamp(_ path: String) -> MailboxStamp? {
  guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
        let modified = attributes[.modificationDate] as? Date,
        let size = (attributes[.size] as? NSNumber)?.uint64Value,
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else {
    return nil
  }
  return MailboxStamp(modified: modified, size: size, inode: inode)
}

private func readMailbox(_ path: String, workers: Int) throws -> MailboxRequest {
  let text = try String(contentsOfFile: path, encoding: .utf8)
  let lines = text.split(whereSeparator: \.isNewline)
  guard let header = lines.first else { throw RankerError.invalid("empty mailbox request") }
  let fields = header.split(separator: "\t", omittingEmptySubsequences: false)
  guard fields.count == 3, fields[0] == "epoch",
        let parsedEpoch = UInt64(fields[1]),
        let count = Int(fields[2]) else {
    throw RankerError.invalid("mailbox header must be epoch<TAB>EPOCH<TAB>ROW_COUNT")
  }
  return MailboxRequest(
    epoch: parsedEpoch,
    rows: try parseRows(lines.dropFirst(), expected: count, workers: workers)
  )
}

private func writeMailbox(_ path: String, epoch: UInt64, scores: [Float]) throws {
  var text = "epoch\t\(epoch)\t\(scores.count)\n"
  for (row, score) in scores.enumerated() { text += "\(row)\t\(score)\n" }
  guard let data = text.data(using: .utf8) else {
    throw RankerError.invalid("could not encode mailbox response")
  }
  try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private struct JSONRequest: Decodable {
  let op: String?
  let id: String
  let rows: [[Float]]
}

private struct JSONTiming: Encodable {
  let preprocessNs: UInt64
  let predictionNs: UInt64
  let totalNs: UInt64
}

private struct JSONResponse: Encodable {
  let op = "score"
  let id: String
  let ok: Bool
  let scores: [Float]?
  let error: String?
  let timingNs: JSONTiming?
}

private func compiledURL(for path: String) async throws -> URL {
  let source = URL(fileURLWithPath: path)
  guard FileManager.default.fileExists(atPath: source.path) else {
    throw RankerError.invalid("model does not exist: \(path)")
  }
  if source.pathExtension == "mlmodelc" { return source }
  return try await MLModel.compileModel(at: source)
}

private func serveMailbox(
  options: Options,
  ranker: Ranker,
  events: EventWriter
) async throws {
  let requestPath = options.requestPath!
  let responsePath = options.responsePath!
  let stopPath = options.stopPath!
  var lastEpoch: UInt64?
  var lastStamp: MailboxStamp?
  var lastError: String?
  var completed: UInt64 = 0
  while !FileManager.default.fileExists(atPath: stopPath),
        kill(options.parentPID, 0) == 0 {
    guard let stamp = mailboxStamp(requestPath), stamp != lastStamp else {
      usleep(options.pollMicroseconds)
      continue
    }
    lastStamp = stamp
    let started = DispatchTime.now().uptimeNanoseconds
    do {
      let request = try readMailbox(requestPath, workers: options.workers)
      if let lastEpoch, request.epoch <= lastEpoch {
        usleep(options.pollMicroseconds)
        continue
      }
      let input = try makeInput(request.rows)
      let predictionStarted = DispatchTime.now().uptimeNanoseconds
      let scores = try await ranker.predict(input, rowCount: request.rows.count)
      let finished = DispatchTime.now().uptimeNanoseconds
      try writeMailbox(responsePath, epoch: request.epoch, scores: scores)
      lastEpoch = request.epoch
      lastError = nil
      completed += 1
      events.stderr(BatchEvent(
        epoch: request.epoch,
        id: nil,
        rows: request.rows.count,
        completedBatches: completed,
        preprocessNs: predictionStarted - started,
        predictionNs: finished - predictionStarted,
        totalNs: finished - started
      ))
    } catch {
      // An atomic producer rename makes malformed data permanent until the next
      // epoch. Avoid flooding stderr while waiting for the producer to replace it.
      let message = String(describing: error)
      if message != lastError {
        events.stderr(ErrorEvent(message: message))
        lastError = message
      }
      usleep(max(options.pollMicroseconds, 10_000))
    }
  }
}

private func serveJSONL(options: Options, ranker: Ranker, events: EventWriter) async {
  let decoder = JSONDecoder()
  var completed: UInt64 = 0
  while let line = readLine() {
    let started = DispatchTime.now().uptimeNanoseconds
    do {
      let request = try decoder.decode(JSONRequest.self, from: Data(line.utf8))
      guard request.op == nil || request.op == "score" else {
        throw RankerError.invalid("unsupported op \(request.op!)")
      }
      let input = try makeInput(request.rows)
      let preprocessed = DispatchTime.now().uptimeNanoseconds
      let scores = try await ranker.predict(input, rowCount: request.rows.count)
      let finished = DispatchTime.now().uptimeNanoseconds
      completed += 1
      events.stdout(JSONResponse(
        id: request.id,
        ok: true,
        scores: scores,
        error: nil,
        timingNs: JSONTiming(
          preprocessNs: preprocessed - started,
          predictionNs: finished - preprocessed,
          totalNs: finished - started
        )
      ))
      events.stderr(BatchEvent(
        epoch: nil,
        id: request.id,
        rows: request.rows.count,
        completedBatches: completed,
        preprocessNs: preprocessed - started,
        predictionNs: finished - preprocessed,
        totalNs: finished - started
      ))
    } catch {
      events.stdout(JSONResponse(
        id: "",
        ok: false,
        scores: nil,
        error: String(describing: error),
        timingNs: nil
      ))
    }
  }
}

@main
private enum Main {
  static func main() async {
    do {
      let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
      guard #available(macOS 14.4, *) else {
        throw RankerError.invalid("MLComputePlan requires macOS 14.4 or newer")
      }
      let modelURL = try await compiledURL(for: options.modelPath)
      let configuration = MLModelConfiguration()
      configuration.computeUnits = options.computeMode.units
      configuration.modelDisplayName = "MetaFlip CoreML Ranker"
      var hints = MLOptimizationHints()
      hints.reshapeFrequency = .infrequent
      hints.specializationStrategy = .fastPrediction
      configuration.optimizationHints = hints
      let plan = try await MLComputePlan.load(contentsOf: modelURL, configuration: configuration)
      let placement = summarize(plan)
      if options.requireANE && !placement.aneVerified {
        throw RankerError.invalid(
          "model is not verified for Neural Engine placement " +
          "(preferred ANE=\(placement.preferredNeuralEngine), GPU=\(placement.preferredGPU))"
        )
      }
      let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
      let ranker = try Ranker(model: model, inputName: options.inputName, outputName: options.outputName)
      let events = EventWriter()
      events.stderr(ReadyEvent(
        pid: getpid(),
        parentPID: options.parentPID,
        compute: options.computeMode,
        preprocessWorkers: options.workers,
        batchSize: batchSize,
        featureCount: featureCount,
        inputName: options.inputName,
        outputName: options.outputName,
        featureSchema: featureSchema,
        featureNames: featureNames,
        compiledModel: modelURL.path,
        anePlacementVerified: placement.aneVerified,
        placement: placement
      ))
      if options.requestPath != nil {
        try await serveMailbox(options: options, ranker: ranker, events: events)
      } else {
        await serveJSONL(options: options, ranker: ranker, events: events)
      }
    } catch {
      FileHandle.standardError.write(Data("coreml_ranker: \(error)\n".utf8))
      Foundation.exit(EXIT_FAILURE)
    }
  }
}
