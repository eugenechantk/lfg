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

    @Test func tableSyntaxInsideFencedCodeStaysCode() {
        let markdown = """
        Before.

        ```markdown
        | A | B |
        | --- | --- |
        | 1 | 2 |
        ```

        After.
        """

        #expect(SelectableMarkdownSections.split(markdown) == [
            .prose("Before."),
            .code("| A | B |\n| --- | --- |\n| 1 | 2 |", depth: 0),
            .prose("After."),
        ])
    }

    @Test func fencedCodeIsIsolatedWithItsIndentationIntact() {
        let markdown = """
        Run this:

        ```swift
        func f() {
            return   // aligned
        }
        ```
        After.
        """

        #expect(SelectableMarkdownSections.split(markdown) == [
            .prose("Run this:"),
            .code("func f() {\n    return   // aligned\n}", depth: 0),
            .prose("After."),
        ])
    }

    @Test func codeInsideListItemKeepsDepthAndListNumbering() {
        let markdown = """
        1. Pull main:
           ```sh
           git pull origin main
             --rebase
           ```
        2. Build
        - bullet
          ~~~
          nested tilde
          ~~~
        """

        #expect(SelectableMarkdownSections.split(markdown) == [
            .prose("1. Pull main:"),
            .code("git pull origin main\n  --rebase", depth: 1),
            .prose("2. Build\n- bullet"),
            .code("nested tilde", depth: 1),
        ])
    }

    @Test func codeInsideNestedListCountsBothLevels() {
        let markdown = """
        - outer
          - inner
            ```
            deep
            ```
        """

        #expect(SelectableMarkdownSections.split(markdown) == [
            .prose("- outer\n  - inner"),
            .code("deep", depth: 2),
        ])
    }

    @Test func unclosedFenceRunsToTheEnd() {
        let markdown = "Intro.\n\n```\nstill streaming\nmore"

        #expect(SelectableMarkdownSections.split(markdown) == [
            .prose("Intro."),
            .code("still streaming\nmore", depth: 0),
        ])
    }

    @Test func longerClosingFenceClosesAndShorterDoesNot() {
        let markdown = "````\n```\ninner\n```\n`````\nAfter."

        #expect(SelectableMarkdownSections.split(markdown) == [
            .code("```\ninner\n```", depth: 0),
            .prose("After."),
        ])
    }

    @Test func inlineTripleBackticksAreNotAFence() {
        let markdown = "```inline code``` in a sentence."

        #expect(SelectableMarkdownSections.split(markdown) == [.prose(markdown)])
    }

    @Test func fourSpaceIndentedFenceOutsideListIsNotAFence() {
        let markdown = "Before.\n\n    ```\n    not a fence\n    ```\n\nAfter."

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
