# std/apple-intelligence

Doof bindings for Apple's on-device FoundationModels `LanguageModelSession`.

The module is session-first: create an `AppleIntelligenceSession` with Doof-side
instructions, call `respond(...)` repeatedly, and the native session keeps its
multi-turn transcript open.

Requirements:

- macOS 26 or newer with the macOS 26 SDK
- Apple Silicon
- Apple Intelligence enabled
- Xcode or the Xcode command-line tools, including `swiftc`, `clang++`, and `xcrun`

## Basic usage

```doof
import { AppleIntelligenceSession } from "std/apple-intelligence"

session := AppleIntelligenceSession(
  "You are a concise assistant. Answer naturally.",
)

answer := try! session.respond("Explain sourdough starter in two sentences.")
followUp := try! session.respond("Now make that explanation friendlier.")
```

## Tool usage

Tool definitions come from Doof description metadata. Register a reflected tool
object with the session and FoundationModels can call its public methods.

```doof
class PantryTools "Kitchen helpers." {
  listIngredients "Lists ingredients available tonight."(): string[] {
    return ["chickpeas", "tomatoes", "spinach"]
  }
}

session := AppleIntelligenceSession("Use pantry tools when they help.")
tools := PantryTools { }
try! session.addTools(tools)
```

See `samples/basic` for a complete executable sample.

Useful commands:

```sh
doof check apple-intelligence
doof build apple-intelligence
doof run apple-intelligence/samples/basic
```
