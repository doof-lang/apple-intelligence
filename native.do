export import class NativeAppleIntelligenceSession from "./apple_intelligence_bridge.hpp" {
  respond(prompt: string): Result<string, string>
  transcriptJson(): Result<string, string>

  addTool(
    name: string,
    description: string,
    inputSchemaJson: string,
    invoke: (argsJson: string): Result<string, string>,
  ): Result<none, string>
}

export import function createNativeAppleIntelligenceSession(instructions: string): NativeAppleIntelligenceSession
  from "./apple_intelligence_bridge.hpp" as createNativeAppleIntelligenceSession
