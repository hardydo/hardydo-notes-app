import Foundation
import HardydoNotesCore

func runOutlineChecks() {
    let text = "# Guide\nintro\n## Setup ##\n```\n# not a heading\n```\n### Install\nstep\n\nOverview\n--------\n| # a |\n|---|\n## Usage"
    let headings = MarkdownOutline.headings(in: text)
    checkEqual(headings.map(\.title), ["Guide", "Setup", "Install", "Overview", "Usage"], "headings skip fences and tables and drop closing hashes")
    checkEqual(headings.map(\.level), [1, 2, 3, 2, 2], "heading levels include setext underlines")
    let path = { (line: Int) in MarkdownOutline.path(headings, toLine: line).map(\.title) }
    checkEqual(path(1), ["Guide"], "text under a heading sits inside it")
    checkEqual(path(7), ["Guide", "Setup", "Install"], "nested headings form the path")
    checkEqual(path(9), ["Guide", "Overview"], "a sibling heading replaces the deeper ones")
    checkEqual(MarkdownOutline.path(MarkdownOutline.headings(in: "text\n# Late"), toLine: 0), [], "lines before the first heading have no path")
}
