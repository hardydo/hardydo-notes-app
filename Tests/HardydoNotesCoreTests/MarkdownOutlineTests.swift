import Foundation
import HardydoNotesCore
import Testing

private func guideHeadings() -> [MarkdownHeading] {
    MarkdownOutline.headings(in: "# Guide\nintro\n## Setup ##\n```\n# not a heading\n```\n### Install\nstep\n\nOverview\n--------\n| # a |\n|---|\n## Usage")
}

@Suite struct MarkdownOutlineTests {
    @Test func headingsSkipFencesAndTablesAndDropClosingHashes() {
        let headings = guideHeadings()
        #expect(headings.map(\.title) == ["Guide", "Setup", "Install", "Overview", "Usage"], "headings skip fences and tables and drop closing hashes")
        #expect(headings.map(\.level) == [1, 2, 3, 2, 2], "heading levels include setext underlines")
    }

    @Test func pathFollowsNestedHeadings() {
        let headings = guideHeadings()
        let path = { (line: Int) in MarkdownOutline.path(headings, toLine: line).map(\.title) }
        #expect(path(1) == ["Guide"], "text under a heading sits inside it")
        #expect(path(7) == ["Guide", "Setup", "Install"], "nested headings form the path")
        #expect(path(9) == ["Guide", "Overview"], "a sibling heading replaces the deeper ones")
        #expect(MarkdownOutline.path(MarkdownOutline.headings(in: "text\n# Late"), toLine: 0) == [], "lines before the first heading have no path")
    }
}
