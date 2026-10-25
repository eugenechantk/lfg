import Testing
@testable import LFGCore

struct TaggedOutputTests {
    @Test func taskResultKeepsExactBody() {
        #expect(TaggedOutput.split("<lfg_task_result>\n{\"summary\":\"Done\"}\n</lfg_task_result>") == [
            .tag(name: "lfg_task_result", content: "\n{\"summary\":\"Done\"}\n")
        ])
    }

    @Test func preservesOrderAndNestedContent() {
        #expect(TaggedOutput.split("Before\n<first>你好</first>\nBetween\n<second>\n<inner>x</inner>\n</second>\nAfter") == [
            .prose("Before\n"), .tag(name: "first", content: "你好"),
            .prose("\nBetween\n"), .tag(name: "second", content: "\n<inner>x</inner>\n"), .prose("\nAfter")
        ])
    }

    @Test func examplesAndIncompleteMarkupStayProse() {
        for text in ["Use <result>x</result> here", "`<result>x</result>`", "<result>pending",
                     "<a>x</b>", "    <result>x</result>", "\t<result>x</result>",
                     "```xml\n<result>x</result>\n```", "~~~~\n<result>x</result>\n~~~~"] {
            #expect(TaggedOutput.split(text) == [.prose(text)])
        }
    }

    @Test func findsOutputAfterFencedExampleAndHandlesEmptyBody() {
        #expect(TaggedOutput.split("```\n<example>x</example>\n```\n<result></result>") == [
            .prose("```\n<example>x</example>\n```\n"), .tag(name: "result", content: "")
        ])
    }

    @Test func inlineBackticksInsideBodyDoNotBlockOutput() {
        #expect(TaggedOutput.split("<result>Use `code`.</result>") == [.tag(name: "result", content: "Use `code`.")])
    }
    @Test func commentsAndUnclosedFencesStayProse() {
        for text in ["<!--\n<result>x</result>\n-->", "<!--\n<result>x</result>",
                     "```xml\n<result>x</result>"] {
            #expect(TaggedOutput.split(text) == [.prose(text)])
        }
    }

    @Test func windowsLineEndingsPreserveContent() {
        #expect(TaggedOutput.split("<result>\r\nDone\r\n</result>\r\n") == [
            .tag(name: "result", content: "\r\nDone\r\n"), .prose("\r\n")
        ])
    }

}
