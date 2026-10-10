import Foundation
import Testing
@testable import LFGCore

@Suite struct ScheduledTaskEditorTests {
    private func draft(expression: String = "0 9 * * 1-5") throws -> ScheduledTaskDraft {
        let json = """
        {"id":"task-a","name":"Review","prompt":"Review changes","cwd":"/tmp","agent":"codex","model":"gpt-6.1-sol","enabled":true,
         "schedule":{"kind":"cron","expression":"\(expression)","timezone":"Asia/Hong_Kong"}}
        """
        return ScheduledTaskDraft(task: try JSONDecoder().decode(ScheduledTaskRecord.self, from: Data(json.utf8)))
    }

    @Test func cronFieldsKeepSavedRangesWhenAnotherFieldChanges() throws {
        var value = try draft()
        value.setCronValue("30", for: .minute)
        value.setCronValue("10", for: .hour)
        #expect(value.expression == "30 10 * * 1-5")
        #expect(value.isValid)
        #expect(value.payload.schedule.expression == "30 10 * * 1-5")
        #expect(value.agent == "codex" && value.model == "gpt-6.1-sol")
        #expect(value.timezone == "Asia/Hong_Kong" && value.cwd == "/tmp")
    }

    @Test func everyCronFieldAcceptsOnlyNumbersInRangeOrAsterisk() throws {
        for field in ScheduledTaskCronField.allCases {
            var value = try draft(expression: "* * * * *")
            for text in ["*", String(field.range.lowerBound), String(field.range.upperBound)] {
                value.setCronValue(text, for: field)
                #expect(value.isValid)
            }
            for text in ["", "-1", "1.5", "hello", "1 2", String(field.range.upperBound + 1)] {
                value.setCronValue(text, for: field)
                #expect(!value.isValid)
            }
        }
    }

    @Test func savedAdvancedFieldsRemainUsableButNewInvalidValuesDoNot() throws {
        var value = try draft(expression: "*/15 9,17 L JAN MON-FRI")
        #expect(value.isValid)
        value.setCronValue("10", for: .hour)
        #expect(value.isValid)
        #expect(value.expression == "*/15 10 L JAN MON-FRI")
        value.setCronValue("*/0", for: .minute)
        #expect(!value.isValid)
        value.setCronValue("*", for: .minute)
        #expect(value.isValid)
    }

    @Test func emptyFieldDoesNotShiftOtherCronValues() throws {
        var value = try draft()
        value.setCronValue("", for: .hour)
        #expect(!value.isValid)
        #expect(value.cronValue(for: .day) == "*")
        #expect(value.cronValue(for: .weekday) == "1-5")
        value.setCronValue("23", for: .hour)
        #expect(value.expression == "0 23 * * 1-5")
        #expect(value.isValid)
    }

    @Test func pastedWhitespaceCannotShiftOrCorruptOtherCronFields() throws {
        var value = try draft()
        value.setCronValue("1 2", for: .minute)
        #expect(!value.isValid)
        #expect(value.cronValue(for: .minute) == "1 2")
        #expect(value.cronValue(for: .hour) == "9")
        #expect(value.cronValue(for: .weekday) == "1-5")
        value.setCronValue("15", for: .minute)
        #expect(value.expression == "15 9 * * 1-5")
        #expect(value.isValid)
    }

    @Test func pickingMetadataPreservesOneTimeInstantAndDefaultModel() throws {
        var value = try draft()
        value.kind = "once"
        value.date = Date(timeIntervalSince1970: 1_800_000_000)
        value.timezone = "America/New_York"
        value.cwd = "/tmp/other"
        value.model = ""
        let payload = value.payload
        #expect(payload.schedule.at == ISO8601DateFormatter().string(from: value.date))
        #expect(payload.schedule.timezone == "America/New_York")
        #expect(payload.model == nil)
        #expect(payload.cwd == "/tmp/other")
        #expect(value.isValid)
    }
}
