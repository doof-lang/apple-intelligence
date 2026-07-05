import { formatJsonValue, parseJsonValue } from "std/json"
import { createNativeAppleIntelligenceSession, NativeAppleIntelligenceSession } from "./native"

export class AppleIntelligenceSession {
  private native: NativeAppleIntelligenceSession

  static constructor(instructions: string): AppleIntelligenceSession {
    return AppleIntelligenceSession {
      native: createNativeAppleIntelligenceSession(instructions),
    }
  }

  respond(prompt: string): Result<string, string> {
    return native.respond(prompt)
  }

  transcriptText(): Result<string, string> {
    return native.transcriptJson()
  }

  transcriptJson(): Result<JsonValue, string> {
    try text := native.transcriptJson()
    return parseJsonValue(text)
  }

  addTool(
    name: string,
    description: string,
    inputSchema: JsonValue,
    invoke: (args: JsonValue): Result<JsonValue, JsonValue>,
  ): Result<void, string> {
    return native.addTool(
      name,
      description,
      formatJsonValue(inputSchema),
      (argsJson: string): Result<string, string> => {
        try args := parseJsonValue(argsJson)
        case invoke(args) {
          s: Success -> return Success(formatJsonValue(s.value))
          f: Failure -> return Failure(formatJsonValue(f.error))
        }
      },
    )
  }

  addTools<T: Reflectable>(tools: T): Result<void, string> {
    meta := T.metadata
    for method of meta.methods {
      try! addTool(
        method.name,
        method.description,
        method.inputSchema,
        (args: JsonValue): Result<JsonValue, JsonValue> => method.invoke(tools, args),
      )
    }
    return Success()
  }
}
