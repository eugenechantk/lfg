import Testing
@testable import LFGCore

struct SelectableMarkdownSectionsTests {
    @Test func proseAndListStayInOneSelectableSection() {
        let markdown = """
        Before the list.

        - first bullet
        - second bullet

        After the list.
        """

        #expect(SelectableMarkdownSections.split(markdown) == [.prose(markdown)])
    }

    @Test func tableIsIsolatedBetweenSelectableProseSections() {
        let markdown = """
        Before the table.

        - still selectable with the paragraph

        | Name | Value |
        | --- | ---: |
        | alpha | 1 |
        | beta | 2 |

        After the table.
        """

        #expect(SelectableMarkdownSections.split(markdown) == [
            .prose("Before the table.\n\n- still selectable with the paragraph"),
            .table("| Name | Value |\n| --- | ---: |\n| alpha | 1 |\n| beta | 2 |"),
            .prose("After the table."),
        ])
    }

    @Test func multipleAndBoundaryTablesPreserveOrder() {
        let markdown = """
        | A | B |
        | --- | --- |
        | 1 | 2 |

        Between.

        Left | Right
        :--- | ---:
        x | y
        """

        #expect(SelectableMarkdownSections.split(markdown) == [
            .table("| A | B |\n| --- | --- |\n| 1 | 2 |"),
            .prose("Between."),
            .table("Left | Right\n:--- | ---:\nx | y"),
        ])
    }

    @Test func tableAtEndDoesNotCreateEmptyProseSection() {
        let markdown = "Intro.\n\n| A |\n| --- |"

        #expect(SelectableMarkdownSections.split(markdown) == [
            .prose("Intro."),
            .table("| A |\n| --- |"),
        ])
    }

    @Test func tableSyntaxInsideFencedCodeStaysSelectableProse() {
        let markdown = """
        Before.

        ```markdown
        | A | B |
        | --- | --- |
        | 1 | 2 |
        ```

        After.
        """

        #expect(SelectableMarkdownSections.split(markdown) == [.prose(markdown)])
    }

    @Test func delimiterLikeTextWithoutHeaderPipeIsNotATable() {
        let markdown = """
        Heading without a pipe
        --- | ---

        More prose.
        """

        #expect(SelectableMarkdownSections.split(markdown) == [.prose(markdown)])
    }

    @Test func fourSpaceIndentedTableSyntaxStaysSelectableProse() {
        let markdown = """
        Before.

            | A | B |
            | --- | --- |

        After.
        """

        #expect(SelectableMarkdownSections.split(markdown) == [.prose(markdown)])
    }
}
