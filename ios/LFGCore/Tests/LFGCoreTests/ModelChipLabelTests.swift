import Foundation
import Testing
@testable import LFGCore

@Suite("S2 composer: model and effort chip")
struct ModelChipLabelTests {
    @Test("Claude ids read as family and version")
    func claude() {
        #expect(ModelChipLabel.model("claude-opus-5-5") == "Opus 5.5")
        #expect(ModelChipLabel.model("claude-sonnet-5") == "Sonnet 5")
        #expect(ModelChipLabel.model("claude-haiku-4-5-20251001") == "Haiku 4.5")
        #expect(ModelChipLabel.model("opus") == "Opus")
        #expect(ModelChipLabel.model("claude-fable-5-1") == "Fable 5.1")
    }

    @Test("GPT ids keep their dotted version")
    func gpt() {
        #expect(ModelChipLabel.model("gpt-5.5") == "GPT-5.5")
        #expect(ModelChipLabel.model("gpt-5.3-codex") == "GPT-5.3 Codex")
    }

    @Test("an unknown id passes through untouched")
    func unknown() {
        #expect(ModelChipLabel.model("o4-mini") == "o4-mini")
    }

    @Test("the chip joins model and effort")
    func chip() {
        #expect(ModelChipLabel.text(model: "claude-opus-5-5", effort: "high") == "Opus 5.5 · High")
        #expect(ModelChipLabel.text(model: "gpt-5.5", effort: "xhigh") == "GPT-5.5 · Extra high")
        #expect(ModelChipLabel.text(model: "claude-haiku-4-5", effort: nil) == "Haiku 4.5")
        #expect(ModelChipLabel.text(model: nil, effort: nil) == "Model")
    }
}
