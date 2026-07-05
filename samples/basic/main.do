import { AppleIntelligenceSession } from "std/apple-intelligence"

class WritingTools "Small deterministic helpers available to the writing assistant." {
  countWords "Counts words in a piece of text."(
    text "The text to count.": string,
  ): int {
    trimmed := text.trim()
    if trimmed == "" {
      return 0
    }
    return trimmed.split(" ").length
  }

  echoLabel "Formats a short labelled note."(
    label "The note label.": string,
    text "The note body.": string,
  ): string {
    return label.trim() + ": " + text.trim()
  }
}

function main(): int {
  session := AppleIntelligenceSession(
    "You are a creative writing assistant. Write naturally and use tools when they help.",
  )
  tools := WritingTools { }
  try! session.addTools(tools)

  case session.respond("Write exactly two short sentences about a robot learning to bake sourdough.") {
    s: Success -> println(s.value)
    f: Failure -> {
      println("Apple Intelligence unavailable: " + f.error)
      return 1
    }
  }

  println("")
  println("=== Follow-up in the same session ===")
  case session.respond("In one sentence, refer to that robot and use a tool to label the note as Summary.") {
    s: Success -> println(s.value)
    f: Failure -> {
      println("Apple Intelligence follow-up failed: " + f.error)
      return 1
    }
  }

  return 0
}
