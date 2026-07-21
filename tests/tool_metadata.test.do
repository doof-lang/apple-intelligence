import { Assert } from "std/assert"
import { formatJsonValue } from "std/json"

class SampleToolResult {
  label: string
  count: int
}

class SampleTools "Tools used to validate Apple Intelligence metadata registration." {
  labelCount "Labels a count for a piece of text."(
    label "The label to attach.": string,
    text "The counted text.": string,
  ): SampleToolResult {
    return SampleToolResult {
      label,
      count: text.trim().split(" ").length,
    }
  }
}

export function testToolMetadataSchemaAndInvoke(): none {
  meta := SampleTools.metadata
  Assert.equal(meta.name, "SampleTools")
  Assert.equal(meta.methods.length, 1)

  method := meta.methods[0]
  Assert.equal(method.name, "labelCount")
  Assert.stringContains(formatJsonValue(method.inputSchema), "\"required\":[\"label\",\"text\"]")

  result := method.invoke(SampleTools { }, { label: "Words", text: "alpha beta" })
  Assert.isTrue(result.isSuccess())
  Assert.equal(formatJsonValue(result.unwrapOr(none)), "{\"label\":\"Words\",\"count\":2}")
}
