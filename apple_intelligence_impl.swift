import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public typealias AIToolCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?,
    UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> UnsafeMutablePointer<CChar>?

private func copiedCString(_ text: String) -> UnsafeMutablePointer<CChar>? {
    strdup(text)
}

private func setError(_ outError: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?, _ message: String) {
    outError?.pointee = copiedCString(message)
}

private func runBlocking<T>(
    _ body: @Sendable @escaping () async throws -> T
) -> Result<T, any Error> {
    nonisolated(unsafe) var result: Result<T, any Error> =
        .failure(NSError(domain: "AppleIntelligence", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "operation did not complete"]))

    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            result = .success(try await body())
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return result
}

@_cdecl("ai_free_string")
public func aiFreeString(_ ptr: UnsafeMutablePointer<CChar>?) {
    free(ptr)
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private func availabilityError() -> String? {
    switch SystemLanguageModel.default.availability {
    case .available:
        return nil
    case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible:
            return "This device does not support Apple Intelligence (Apple Silicon required)"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled in System Settings"
        case .modelNotReady:
            return "The Apple Intelligence model is still downloading; try again later"
        @unknown default:
            return "Apple Intelligence is unavailable"
        }
    @unknown default:
        return "Apple Intelligence is unavailable"
    }
}

@available(macOS 26.0, *)
private struct DynamicToolArguments: ConvertibleFromGeneratedContent, Sendable {
    let content: GeneratedContent

    init(_ content: GeneratedContent) throws {
        self.content = content
    }
}

@available(macOS 26.0, *)
private struct DynamicDoofTool: Tool {
    typealias Arguments = DynamicToolArguments
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let callbackContextAddress: UInt
    let callback: AIToolCallback

    var includesSchemaInInstructions: Bool { true }

    func call(arguments: DynamicToolArguments) async throws -> String {
        var error: UnsafeMutablePointer<CChar>? = nil
        let argsJson = arguments.content.jsonString
        let raw = argsJson.withCString { cString in
            callback(UnsafeMutableRawPointer(bitPattern: callbackContextAddress), cString, &error)
        }
        if let raw {
            defer { aiFreeString(raw) }
            return String(cString: raw)
        }
        defer { aiFreeString(error) }
        throw NSError(
            domain: "AppleIntelligenceTool",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: error.map { String(cString: $0) } ?? "tool call failed"]
        )
    }
}

@available(macOS 26.0, *)
private final class AISessionBox {
    var session: LanguageModelSession
    var tools: [DynamicDoofTool] = []
    let instructions: String

    init(instructions: String) {
        self.instructions = instructions
        self.session = LanguageModelSession(instructions: instructions)
    }

    func rebuildSession() {
        session = LanguageModelSession(tools: tools, instructions: instructions)
    }
}

@available(macOS 26.0, *)
private func requireBox(_ opaque: UnsafeMutableRawPointer?) throws -> AISessionBox {
    guard let opaque else {
        throw NSError(domain: "AppleIntelligence", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "missing Apple Intelligence session"])
    }
    return Unmanaged<AISessionBox>.fromOpaque(opaque).takeUnretainedValue()
}

@available(macOS 26.0, *)
private struct SchemaConverter {
    let rootName: String
    let root: [String: Any]
    let defs: [String: Any]

    init(rootName: String, jsonText: String) throws {
        guard let data = jsonText.data(using: .utf8) else {
            throw Self.schemaError("schema is not valid UTF-8")
        }
        let value = try JSONSerialization.jsonObject(with: data)
        guard var object = value as? [String: Any] else {
            throw Self.schemaError("schema root must be a JSON object")
        }
        let extractedDefs = object.removeValue(forKey: "$defs") as? [String: Any] ?? [:]
        self.rootName = rootName
        self.root = object
        self.defs = extractedDefs
    }

    func generationSchema() throws -> GenerationSchema {
        let rootSchema = try dynamicSchema(name: rootName + "Arguments", schema: root)
        let dependencies = try defs.map { key, value -> DynamicGenerationSchema in
            guard let object = value as? [String: Any] else {
                throw Self.schemaError("$defs.\(key) must be an object")
            }
            return try dynamicSchema(name: key, schema: object)
        }
        return try GenerationSchema(root: rootSchema, dependencies: dependencies)
    }

    private func dynamicSchema(name: String, schema: [String: Any]) throws -> DynamicGenerationSchema {
        if let ref = schema["$ref"] as? String {
            guard ref.hasPrefix("#/$defs/") else {
                throw Self.schemaError("unsupported JSON Schema reference \(ref)")
            }
            return DynamicGenerationSchema(referenceTo: String(ref.dropFirst("#/$defs/".count)))
        }

        if let choices = schema["anyOf"] as? [[String: Any]] {
            return DynamicGenerationSchema(
                name: name,
                anyOf: try choices.enumerated().map { index, choice in
                    try dynamicSchema(name: "\(name)Choice\(index)", schema: choice)
                }
            )
        }

        if let enumValues = schema["enum"] as? [String] {
            return DynamicGenerationSchema(name: name, anyOf: enumValues)
        }

        let description = schema["description"] as? String
        let type = schema["type"] as? String
        switch type {
        case "object":
            let properties = schema["properties"] as? [String: Any] ?? [:]
            let required = Set(schema["required"] as? [String] ?? [])
            let converted = try properties.map { propertyName, propertyValue -> DynamicGenerationSchema.Property in
                guard let propertySchema = propertyValue as? [String: Any] else {
                    throw Self.schemaError("property \(propertyName) schema must be an object")
                }
                return DynamicGenerationSchema.Property(
                    name: propertyName,
                    description: propertySchema["description"] as? String,
                    schema: try dynamicSchema(name: "\(name)_\(propertyName)", schema: propertySchema),
                    isOptional: !required.contains(propertyName)
                )
            }
            return DynamicGenerationSchema(name: name, description: description, properties: converted)

        case "array":
            guard let itemSchema = schema["items"] as? [String: Any] else {
                throw Self.schemaError("array schema must include object-valued items")
            }
            return DynamicGenerationSchema(arrayOf: try dynamicSchema(name: "\(name)Item", schema: itemSchema))

        case "string":
            return DynamicGenerationSchema(type: String.self)
        case "integer":
            return DynamicGenerationSchema(type: Int.self)
        case "number":
            return DynamicGenerationSchema(type: Double.self)
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self)
        case "null":
            if #available(macOS 26.4, *) {
                return .null
            }
            throw Self.schemaError("null schemas require macOS 26.4 or later")
        case .none:
            throw Self.schemaError("schema is missing a type")
        default:
            throw Self.schemaError("unsupported JSON Schema type \(type!)")
        }
    }

    private static func schemaError(_ message: String) -> NSError {
        NSError(domain: "AppleIntelligenceSchema", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
#endif

@_cdecl("ai_session_create")
public func aiSessionCreate(
    _ instructions: UnsafePointer<CChar>,
    _ outError: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> UnsafeMutableRawPointer? {
    let instructionsText = String(cString: instructions)

    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
        if let message = availabilityError() {
            setError(outError, message)
            return nil
        }
        let box = AISessionBox(instructions: instructionsText)
        return Unmanaged.passRetained(box).toOpaque()
    }
    #endif

    setError(outError, "Apple Intelligence requires macOS 26.0 or later with FoundationModels")
    return nil
}

@_cdecl("ai_session_release")
public func aiSessionRelease(_ session: UnsafeMutableRawPointer?) {
    guard let session else { return }
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
        Unmanaged<AISessionBox>.fromOpaque(session).release()
    }
    #endif
}

@_cdecl("ai_session_respond")
public func aiSessionRespond(
    _ session: UnsafeMutableRawPointer?,
    _ prompt: UnsafePointer<CChar>,
    _ outError: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> UnsafeMutablePointer<CChar>? {
    let promptText = String(cString: prompt)

    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
        let sessionAddress = UInt(bitPattern: session)
        let result = runBlocking { () async throws -> String in
            let box = try requireBox(UnsafeMutableRawPointer(bitPattern: sessionAddress))
            let response = try await box.session.respond(to: promptText)
            return response.content
        }
        switch result {
        case .success(let text):
            return copiedCString(text)
        case .failure(let error):
            setError(outError, "Apple Intelligence error: \(error.localizedDescription)")
            return nil
        }
    }
    #endif

    setError(outError, "Apple Intelligence requires macOS 26.0 or later with FoundationModels")
    return nil
}

@_cdecl("ai_session_transcript_json")
public func aiSessionTranscriptJson(
    _ session: UnsafeMutableRawPointer?,
    _ outError: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> UnsafeMutablePointer<CChar>? {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
        do {
            let box = try requireBox(session)
            let data = try JSONEncoder().encode(box.session.transcript)
            return copiedCString(String(data: data, encoding: .utf8) ?? "[]")
        } catch {
            setError(outError, "Could not encode transcript: \(error.localizedDescription)")
            return nil
        }
    }
    #endif

    setError(outError, "Apple Intelligence requires macOS 26.0 or later with FoundationModels")
    return nil
}

@_cdecl("ai_session_add_tool")
public func aiSessionAddTool(
    _ session: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<CChar>,
    _ description: UnsafePointer<CChar>,
    _ inputSchemaJson: UnsafePointer<CChar>,
    _ callbackContext: UnsafeMutableRawPointer?,
    _ callback: AIToolCallback?,
    _ outError: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> Int32 {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
        do {
            guard let callback else {
                setError(outError, "missing tool callback")
                return 0
            }
            let box = try requireBox(session)
            let toolName = String(cString: name)
            let schema = try SchemaConverter(
                rootName: toolName,
                jsonText: String(cString: inputSchemaJson)
            ).generationSchema()

            box.tools.append(DynamicDoofTool(
                name: toolName,
                description: String(cString: description),
                parameters: schema,
                callbackContextAddress: UInt(bitPattern: callbackContext),
                callback: callback
            ))
            box.rebuildSession()
            return 1
        } catch {
            setError(outError, "Could not add tool: \(error.localizedDescription)")
            return 0
        }
    }
    #endif

    setError(outError, "Apple Intelligence requires macOS 26.0 or later with FoundationModels")
    return 0
}
